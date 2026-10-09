/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:podship_console_server/src/generated/integrations/models/provider.dart'
    as _iir3qt9b;
import 'package:serverpod/serverpod.dart' as _is;
import 'package:serverpod_auth_core_server/serverpod_auth_core_server.dart'
    as _iacs;
import 'package:serverpod_auth_idp_server/serverpod_auth_idp_server.dart'
    as _iais;
import '../auth/email_code_endpoint.dart' as _in3cimlf;
import '../auth/jwt_refresh_endpoint.dart' as _inwq3ztq;
import '../endpoints/integrations_endpoint.dart' as _iipgqonr;
import '../endpoints/me_endpoint.dart' as _io0suj43;

class Endpoints extends _is.EndpointDispatch {
  @override
  void initializeEndpoints(_is.Server server) {
    var endpoints = <String, _is.Endpoint>{
      'emailCode': _in3cimlf.EmailCodeEndpoint()
        ..initialize(
          server,
          'emailCode',
          null,
        ),
      'jwtRefresh': _inwq3ztq.JwtRefreshEndpoint()
        ..initialize(
          server,
          'jwtRefresh',
          null,
        ),
      'integrations': _iipgqonr.IntegrationsEndpoint()
        ..initialize(
          server,
          'integrations',
          null,
        ),
      'me': _io0suj43.MeEndpoint()
        ..initialize(
          server,
          'me',
          null,
        ),
    };
    connectors['emailCode'] = _is.EndpointConnector(
      name: 'emailCode',
      endpoint: endpoints['emailCode']!,
      methodConnectors: {
        'requestCode': _is.MethodConnector(
          name: 'requestCode',
          params: {
            'email': _is.ParameterDescription(
              name: 'email',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'locale': _is.ParameterDescription(
              name: 'locale',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['emailCode'] as _in3cimlf.EmailCodeEndpoint)
                  .requestCode(
                    session,
                    params['email'],
                    params['locale'],
                  ),
        ),
        'verifyCode': _is.MethodConnector(
          name: 'verifyCode',
          params: {
            'email': _is.ParameterDescription(
              name: 'email',
              type: _is.getType<String>(),
              nullable: false,
            ),
            'code': _is.ParameterDescription(
              name: 'code',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['emailCode'] as _in3cimlf.EmailCodeEndpoint)
                  .verifyCode(
                    session,
                    params['email'],
                    params['code'],
                  ),
        ),
        'redeemLink': _is.MethodConnector(
          name: 'redeemLink',
          params: {
            'token': _is.ParameterDescription(
              name: 'token',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['emailCode'] as _in3cimlf.EmailCodeEndpoint)
                  .redeemLink(
                    session,
                    params['token'],
                  ),
        ),
      },
    );
    connectors['jwtRefresh'] = _is.EndpointConnector(
      name: 'jwtRefresh',
      endpoint: endpoints['jwtRefresh']!,
      methodConnectors: {
        'refreshAccessToken': _is.MethodConnector(
          name: 'refreshAccessToken',
          params: {
            'refreshToken': _is.ParameterDescription(
              name: 'refreshToken',
              type: _is.getType<String?>(),
              nullable: true,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['jwtRefresh'] as _inwq3ztq.JwtRefreshEndpoint)
                      .refreshAccessToken(
                        session,
                        refreshToken: params['refreshToken'],
                      ),
        ),
      },
    );
    connectors['integrations'] = _is.EndpointConnector(
      name: 'integrations',
      endpoint: endpoints['integrations']!,
      methodConnectors: {
        'list': _is.MethodConnector(
          name: 'list',
          params: {},
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['integrations'] as _iipgqonr.IntegrationsEndpoint)
                      .list(session),
        ),
        'cloudflareTokenUrl': _is.MethodConnector(
          name: 'cloudflareTokenUrl',
          params: {},
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['integrations'] as _iipgqonr.IntegrationsEndpoint)
                      .cloudflareTokenUrl(session),
        ),
        'saveCloudflare': _is.MethodConnector(
          name: 'saveCloudflare',
          params: {
            'token': _is.ParameterDescription(
              name: 'token',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['integrations'] as _iipgqonr.IntegrationsEndpoint)
                      .saveCloudflare(
                        session,
                        params['token'],
                      ),
        ),
        'startAws': _is.MethodConnector(
          name: 'startAws',
          params: {},
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['integrations'] as _iipgqonr.IntegrationsEndpoint)
                      .startAws(session),
        ),
        'disconnect': _is.MethodConnector(
          name: 'disconnect',
          params: {
            'provider': _is.ParameterDescription(
              name: 'provider',
              type: _is.getType<_iir3qt9b.IntegrationProvider>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['integrations'] as _iipgqonr.IntegrationsEndpoint)
                      .disconnect(
                        session,
                        params['provider'],
                      ),
        ),
        'check': _is.MethodConnector(
          name: 'check',
          params: {
            'provider': _is.ParameterDescription(
              name: 'provider',
              type: _is.getType<_iir3qt9b.IntegrationProvider>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['integrations'] as _iipgqonr.IntegrationsEndpoint)
                      .check(
                        session,
                        params['provider'],
                      ),
        ),
      },
    );
    connectors['me'] = _is.EndpointConnector(
      name: 'me',
      endpoint: endpoints['me']!,
      methodConnectors: {
        'get': _is.MethodConnector(
          name: 'get',
          params: {},
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['me'] as _io0suj43.MeEndpoint).get(session),
        ),
      },
    );
    modules['serverpod_auth_idp'] = _iais.Endpoints()
      ..initializeEndpoints(server);
    modules['serverpod_auth_core'] = _iacs.Endpoints()
      ..initializeEndpoints(server);
  }
}
