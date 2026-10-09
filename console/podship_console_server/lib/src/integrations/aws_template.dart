// The CloudFormation template that connects a workspace's AWS account
// (decision: AWS through a role with web identity, no access keys).
//
// One static template for every workspace and every console. The vendor
// hosts it in a public, versioned S3 object (`aws/connect-v1.json`); the
// console opens it as a quick-create link with every parameter filled in, so
// the person only ticks the IAM box and clicks "Create stack". After the
// connect, the console keeps the S3 object up to date itself (role policy
// `TemplateMaintenance`). `console/aws/connect-v1.json` is this file,
// written by `dart run tool/console_tool.dart aws-template`.

import 'dart:convert';

class AwsTemplate {
  /// The object name of the current version. A change to [build] that
  /// changes the stack's behavior gets a new version.
  static const version = 'v1';
  static const objectKey = 'aws/connect-$version.json';

  static const roleName = 'podship-console';
  static const boundaryName = 'podship-ses-sender';
  static const userPath = '/podship-ses/';
  static const stackName = 'podship';

  static const sesActions = [
    'ses:GetAccount',
    'ses:ListEmailIdentities',
    'ses:GetEmailIdentity',
    'ses:CreateEmailIdentity',
    'ses:DeleteEmailIdentity',
    'ses:PutEmailIdentityMailFromAttributes',
    'ses:TagResource',
    'ses:SendEmail',
    'ses:SendRawEmail',
  ];

  static const _lambda = '''
import json, urllib.request, cfnresponse

def handler(event, context):
    props = event.get("ResourceProperties", {})
    body = json.dumps({
        "code": props.get("ExternalId"),
        "request_type": event["RequestType"],
        "account_id": props.get("AccountId"),
        "role_arn": props.get("RoleArn"),
        "stack_id": event.get("StackId"),
        "region": props.get("Region"),
        "template_version": props.get("TemplateVersion"),
    }).encode()
    status = cfnresponse.SUCCESS
    reason = "podship console answered"
    try:
        req = urllib.request.Request(props["CallbackUrl"], data=body, method="POST", headers={
            "Content-Type": "application/json",
            "User-Agent": "podship-cloudformation/1",
        })
        urllib.request.urlopen(req, timeout=20).read()
    except Exception as e:
        reason = "the podship console did not answer: %s" % e
        print(reason)
        # A failed connect stops the stack; a delete always goes on.
        if event["RequestType"] == "Create":
            status = cfnresponse.FAILED
    cfnresponse.send(event, context, status, {}, reason=reason)
''';

  /// The trust policy as a string, because its condition keys hold the
  /// issuer host and CloudFormation cannot build a JSON key from a
  /// parameter.
  static const _trust =
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",'
      '"Principal":{"Federated":"\${PodshipOidcProvider}"},'
      '"Action":"sts:AssumeRoleWithWebIdentity",'
      '"Condition":{"StringEquals":{'
      '"\${IssuerHost}:aud":"sts.amazonaws.com",'
      '"\${IssuerHost}:sub":"\${Subject}"}}}]}';

  static String build() {
    final user = {
      'Fn::Sub':
          'arn:\${AWS::Partition}:iam::\${AWS::AccountId}:user$userPath*',
    };
    final t = {
      'AWSTemplateFormatVersion': '2010-09-09',
      'Description':
          'podship console ($version): lets a podship workspace manage Amazon '
          'SES and per-app send-only users. No access keys: podship assumes '
          'the role $roleName with a token signed by its console.',
      'Parameters': {
        'IssuerHost': {
          'Type': 'String',
          'Description':
              'The podship console host, for example podship.densitylabs.io.',
          'AllowedPattern': r'^[a-z0-9.-]+$',
        },
        'Subject': {
          'Type': 'String',
          'Description': 'The workspace, for example workspace:density-labs.',
          'AllowedPattern': r'^workspace:[a-z0-9-]+$',
        },
        'ExternalId': {
          'Type': 'String',
          'Description':
              'One-time connect code from the podship console. It expires after 24 hours.',
          'AllowedPattern': r'^[A-Za-z0-9]{20,64}$',
        },
        'CallbackUrl': {
          'Type': 'String',
          'Description': 'Where the stack tells the console that it exists.',
          'AllowedPattern': r'^https://.+$',
        },
      },
      'Resources': {
        'PodshipOidcProvider': {
          'Type': 'AWS::IAM::OIDCProvider',
          'Properties': {
            'Url': {'Fn::Sub': r'https://${IssuerHost}'},
            'ClientIdList': ['sts.amazonaws.com'],
          },
        },
        'PodshipSenderBoundary': {
          'Type': 'AWS::IAM::ManagedPolicy',
          'Properties': {
            'ManagedPolicyName': boundaryName,
            'Description':
                'Boundary of the per-app SES users podship makes: send email only.',
            'PolicyDocument': {
              'Version': '2012-10-17',
              'Statement': [
                {
                  'Effect': 'Allow',
                  'Action': ['ses:SendEmail', 'ses:SendRawEmail'],
                  'Resource': '*',
                },
              ],
            },
          },
        },
        'PodshipRole': {
          'Type': 'AWS::IAM::Role',
          'Properties': {
            'RoleName': roleName,
            'MaxSessionDuration': 3600,
            'AssumeRolePolicyDocument': {'Fn::Sub': _trust},
            'Policies': [
              {
                'PolicyName': 'podship-ses',
                'PolicyDocument': {
                  'Version': '2012-10-17',
                  'Statement': [
                    {
                      'Sid': 'Ses',
                      'Effect': 'Allow',
                      'Action': sesActions,
                      'Resource': '*',
                    },
                    {
                      'Sid': 'CreateSendingUsers',
                      'Effect': 'Allow',
                      'Action': 'iam:CreateUser',
                      'Resource': user,
                      'Condition': {
                        'StringEquals': {
                          'iam:PermissionsBoundary': {
                            'Ref': 'PodshipSenderBoundary',
                          },
                        },
                      },
                    },
                    {
                      'Sid': 'ManageSendingUsers',
                      'Effect': 'Allow',
                      'Action': [
                        'iam:GetUser',
                        'iam:DeleteUser',
                        'iam:TagUser',
                        'iam:PutUserPolicy',
                        'iam:GetUserPolicy',
                        'iam:DeleteUserPolicy',
                        'iam:ListUserPolicies',
                        'iam:CreateAccessKey',
                        'iam:DeleteAccessKey',
                        'iam:ListAccessKeys',
                      ],
                      'Resource': user,
                    },
                    {
                      'Sid': 'KeepTheBoundary',
                      'Effect': 'Deny',
                      'Action': [
                        'iam:DeleteUserPermissionsBoundary',
                        'iam:PutUserPermissionsBoundary',
                      ],
                      'Resource': '*',
                    },
                    {
                      'Sid': 'TemplateMaintenance',
                      'Effect': 'Allow',
                      'Action': ['s3:GetObject', 's3:PutObject'],
                      'Resource': {
                        'Fn::Sub':
                            'arn:\${AWS::Partition}:s3:::podship-templates-\${AWS::AccountId}/aws/*',
                      },
                    },
                  ],
                },
              },
            ],
          },
        },
        'PodshipCallbackRole': {
          'Type': 'AWS::IAM::Role',
          'Properties': {
            'AssumeRolePolicyDocument': {
              'Version': '2012-10-17',
              'Statement': [
                {
                  'Effect': 'Allow',
                  'Principal': {'Service': 'lambda.amazonaws.com'},
                  'Action': 'sts:AssumeRole',
                },
              ],
            },
            'ManagedPolicyArns': [
              {
                'Fn::Sub':
                    'arn:\${AWS::Partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole',
              },
            ],
          },
        },
        'PodshipCallback': {
          'Type': 'AWS::Lambda::Function',
          'Properties': {
            'Description':
                'Tells the podship console that this stack exists (or was deleted).',
            'Runtime': 'python3.12',
            'Handler': 'index.handler',
            'Timeout': 60,
            'Role': {
              'Fn::GetAtt': ['PodshipCallbackRole', 'Arn'],
            },
            'Code': {'ZipFile': _lambda},
          },
        },
        'PodshipConnect': {
          'Type': 'Custom::PodshipConnect',
          'DependsOn': ['PodshipRole'],
          'Properties': {
            'ServiceToken': {
              'Fn::GetAtt': ['PodshipCallback', 'Arn'],
            },
            'CallbackUrl': {'Ref': 'CallbackUrl'},
            'ExternalId': {'Ref': 'ExternalId'},
            'TemplateVersion': version,
            'AccountId': {'Ref': 'AWS::AccountId'},
            'Region': {'Ref': 'AWS::Region'},
            'RoleArn': {
              'Fn::GetAtt': ['PodshipRole', 'Arn'],
            },
          },
        },
      },
      'Outputs': {
        'RoleArn': {
          'Value': {
            'Fn::GetAtt': ['PodshipRole', 'Arn'],
          },
        },
      },
    };
    return '${const JsonEncoder.withIndent('  ').convert(t)}\n';
  }

  /// The quick-create link (INT-11): the CloudFormation console with the
  /// template, the stack name and every parameter filled in.
  static String quickCreateUrl({
    required String templateUrl,
    required String region,
    required String issuerHost,
    required String subject,
    required String externalId,
    required String callbackUrl,
  }) {
    final q = {
      'templateURL': templateUrl,
      'stackName': stackName,
      'param_IssuerHost': issuerHost,
      'param_Subject': subject,
      'param_ExternalId': externalId,
      'param_CallbackUrl': callbackUrl,
    };
    final query = q.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return 'https://$region.console.aws.amazon.com/cloudformation/home'
        '?region=$region#/stacks/create/review?$query';
  }

  /// The bucket policy the vendor sets: public read of `aws/*` only.
  static String bucketPolicy(String bucket) =>
      '${const JsonEncoder.withIndent('  ').convert({
        'Version': '2012-10-17',
        'Statement': [
          {
            'Sid': 'PublicReadOfConnectTemplates',
            'Effect': 'Allow',
            'Principal': '*',
            'Action': 's3:GetObject',
            'Resource': 'arn:aws:s3:::$bucket/aws/*',
          },
        ],
      })}\n';
}
