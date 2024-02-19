# frozen_string_literal: true

Rails.application.config.middleware.use OmniAuth::Builder do
  provider(
    :boxyhqsso,
    'dummy',
    ENV['CLIENT_SECRET_VERIFIER'],
    ENV['JACKSON_URL'],
    callback_path: '/auth/boxyhqsso/callback',
    authorize_params: {
      scope: 'openid',
    },
  )
end
