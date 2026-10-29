# frozen_string_literal: true

module SignInWithXSigner
  def siwx_evm_key
    OpenSSL::PKey::EC.generate("secp256k1")
  end

  def siwx_svm_key
    OpenSSL::PKey.generate_key("ED25519")
  end

  def siwx_address(key)
    if key.is_a?(OpenSSL::PKey::EC)
      public_key = key.public_key.to_octet_string(:uncompressed)
      X402::Network.checksum("0x#{X402::Keccak256.hexdigest(public_key.byteslice(1, 64)).last(40)}")
    else
      X402::Base58.encode(key.raw_public_key)
    end
  end

  def signed_siwx(key, **fields)
    evm = key.is_a?(OpenSSL::PKey::EC)
    payload = {
      "domain" => "api.example.com",
      "address" => siwx_address(key),
      "statement" => "Sign in to use your credits",
      "uri" => "https://api.example.com/v1/generate",
      "version" => "1",
      "chainId" => evm ? "eip155:84532" : "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1",
      "type" => evm ? "eip191" : "ed25519",
      "nonce" => SecureRandom.alphanumeric(32),
      "issuedAt" => Time.current.utc.iso8601(3)
    }.merge(fields.transform_keys(&:to_s)).compact
    message = X402::SignInWithX::Message.build(payload)
    signature = evm ? siwx_evm_signature(key, message) : X402::Base58.encode(key.sign(nil, message))

    payload.merge("signature" => signature)
  end

  def siwx_evm_signature(key, message)
    digest = X402::Keccak256.digest("\x19Ethereum Signed Message:\n#{message.bytesize}#{message}")
    r, s = OpenSSL::ASN1.decode(key.sign_raw(nil, digest)).value.map { |integer| integer.value.to_i }
    rs = [format("%064x%064x", r, s)].pack("H*")
    public_key = key.public_key.to_octet_string(:uncompressed)
    signature = [27, 28].map { |v| rs + v.chr }.find do |candidate|
      X402::Secp256k1.recover_public_key(digest:, signature: candidate) == public_key
    end

    "0x#{signature.unpack1("H*")}"
  end
end
