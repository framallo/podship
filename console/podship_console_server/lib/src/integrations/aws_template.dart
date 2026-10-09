// The CloudFormation template that connects a workspace's AWS account
// (decision: AWS through a role with web identity, no access keys).
//
// The template is made per connect: the one-time code, the issuer and the
// workspace subject are literal values, because CloudFormation cannot build
// the condition keys of a trust policy at run time.

import 'dart:convert';

class AwsTemplate {
  /// The role podship assumes.
  static const roleName = 'podship-console';

  /// The boundary every per-app sending user must carry.
  static const boundaryName = 'podship-ses-sender';

  /// The IAM path of per-app sending users (`presente-ses`).
  static const userPath = '/podship-ses/';

  /// SES actions podship uses (README "AWS credentials for SES").
  static const sesActions = [
    'ses:GetAccount',
    'ses:ListEmailIdentities',
    'ses:GetEmailIdentity',
    'ses:CreateEmailIdentity',
    'ses:DeleteEmailIdentity',
    'ses:PutEmailIdentityMailFromAttributes',
    'ses:TagResource',
    'ses:SendEmail',
  ];

  /// The template as JSON (CloudFormation reads JSON and YAML).
  static String build({
    required String issuerUrl,
    required String subject,
    required String callbackUrl,
    required String code,
    required String workspace,
  }) {
    final host = Uri.parse(issuerUrl).authority;
    final lambda =
        '''
import json, urllib.request, cfnresponse

URL = ${jsonEncode(callbackUrl)}
CODE = ${jsonEncode(code)}

def handler(event, context):
    props = event.get("ResourceProperties", {})
    body = json.dumps({
        "code": CODE,
        "request_type": event["RequestType"],
        "account_id": props.get("AccountId"),
        "role_arn": props.get("RoleArn"),
        "stack_id": event.get("StackId"),
        "region": props.get("Region"),
    }).encode()
    status = cfnresponse.SUCCESS
    reason = "podship console answered"
    try:
        req = urllib.request.Request(URL, data=body, method="POST", headers={
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
    final t = {
      'AWSTemplateFormatVersion': '2010-09-09',
      'Description':
          'podship console: lets the workspace "$workspace" manage Amazon SES '
          'and per-app SES sending users. No access keys: podship assumes '
          'the role $roleName with a token signed by $host.',
      'Resources': {
        'PodshipOidcProvider': {
          'Type': 'AWS::IAM::OIDCProvider',
          'Properties': {
            'Url': issuerUrl,
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
            'AssumeRolePolicyDocument': {
              'Version': '2012-10-17',
              'Statement': [
                {
                  'Effect': 'Allow',
                  'Principal': {
                    'Federated': {'Ref': 'PodshipOidcProvider'},
                  },
                  'Action': 'sts:AssumeRoleWithWebIdentity',
                  'Condition': {
                    'StringEquals': {
                      '$host:aud': 'sts.amazonaws.com',
                      '$host:sub': subject,
                    },
                  },
                },
              ],
            },
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
                      'Resource': {
                        'Fn::Sub':
                            'arn:\${AWS::Partition}:iam::\${AWS::AccountId}:user$userPath*',
                      },
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
                      'Resource': {
                        'Fn::Sub':
                            'arn:\${AWS::Partition}:iam::\${AWS::AccountId}:user$userPath*',
                      },
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
            'Code': {'ZipFile': lambda},
          },
        },
        'PodshipConnect': {
          'Type': 'Custom::PodshipConnect',
          'DependsOn': ['PodshipRole'],
          'Properties': {
            'ServiceToken': {
              'Fn::GetAtt': ['PodshipCallback', 'Arn'],
            },
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
    return const JsonEncoder.withIndent('  ').convert(t);
  }

  /// The CloudFormation "Create stack" page, where the person uploads the
  /// template (INT-11).
  static String consoleUrl(String region) =>
      'https://$region.console.aws.amazon.com/cloudformation/home'
      '?region=$region#/stacks/create';
}
