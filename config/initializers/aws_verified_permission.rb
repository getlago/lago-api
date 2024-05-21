require 'aws-sdk-verifiedpermissions' # require the specific AWS SDK you're using

$aws_avp_client = Aws.config.update({
  region: 'ap-southeast-1',
  credentials: Aws::Credentials.new(ENV.fetch('AWS_ACCESS_KEY_ID', nil), ENV.fetch('AWS_SECRET_ACCESS_KEY', nil))
})
