# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each, type: :admin) do
    allow(Google::Auth::IDTokens)
      .to receive(:verify_oidc)
      .and_return({ email: 'test@getlago.com' })
  end
end
