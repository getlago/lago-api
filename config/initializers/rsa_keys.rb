# frozen_string_literal: true

if Rails.env.development? || Rails.env.test?
  private_key_string = File.read(Rails.root.join('.rsa_private.pem'))
  RsaPrivateKey = OpenSSL::PKey::RSA.new(private_key_string)
  RsaPublicKey = RsaPrivateKey.public_key
else
  RsaPrivateKey = ENV['RSA_PRIVATE_KEY']
  RsaPublicKey = ENV['RSA_PUBLIC_KEY']
end
