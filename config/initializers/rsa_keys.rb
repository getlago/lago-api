# frozen_string_literal: true

private_key_string = if Rails.env.development? || Rails.env.test?
  File.read(Rails.root.join(".rsa_private.pem"))
else
  Base64.decode64(ENV["LAGO_RSA_PRIVATE_KEY"])
end

RsaPrivateKey = OpenSSL::PKey::RSA.new(private_key_string)
RsaPublicKey = RsaPrivateKey.public_key
