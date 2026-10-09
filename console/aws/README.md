# AWS connect template (vendor files)

`connect-v1.json` is the CloudFormation template the console opens as a
quick-create link (podship-design `specs/integrations.md`, INT-11). It is
written by `dart run tool/console_tool.dart aws-template` in
`podship_console_server` and a test checks it equals `AwsTemplate.build()`.

Hosting (vendor setup, once, not a user step):

| Setting | Value |
|---|---|
| Bucket | `podship-templates-<account id>`, region `us-west-1` |
| Object | `aws/connect-v1.json`, `Content-Type: application/json` |
| Versioning | Enabled |
| Block Public Access | Block public ACLs: on (both). Block public bucket policies: off (both). |
| Object ownership | Bucket owner enforced (ACLs off) |
| Bucket policy | `bucket-policy.json` with `ACCOUNT_ID` replaced: public read of `aws/*` only; every other key stays private |

Then set the console's URL and redeploy:
`podship env set --env production CONSOLE_AWS_TEMPLATE_URL=https://podship-templates-<account id>.s3.us-west-1.amazonaws.com/aws/connect-v1.json`

After a workspace connects, the role's `TemplateMaintenance` statement lets
the console put new versions of `aws/*` in that bucket; the console uploads
the template when the public object differs.
