# frozen_string_literal: true

require 'aws-sdk-verifiedpermissions'

module AwsAvp
  def self.init
    Aws::VerifiedPermissions::Client.new({
      region: 'ap-southeast-1',
      credentials: Aws::Credentials.new(ENV.fetch('AWS_ACCESS_KEY_ID', nil), ENV.fetch('AWS_SECRET_ACCESS_KEY', nil))
    })
  end
end
