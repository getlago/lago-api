module OtpAuthenticatable
  extend ActiveSupport::Concern

  included do
    attribute :otp_attempt, :string
  end

  def otp_enabled?
    !!(otp_secret.present? && otp_required_for_login)
  end

  def set_otp_secret!
    update!(otp_secret: ::ROTP::Base32.random)
  end

  def set_otp_backup_codes!(count = 5, length = 14)
    codes = []
    count.times do
      codes.append(SecureRandom.hex(length / 2))
    end
    update!(otp_backup_codes: codes)
  end

  def verify_otp!(code)
    return true if consume_otp!(code)
    return true if consume_backup_code!(code)

    false
  end

  def totp(issuer = 'Lago')
    @totp ||= ::ROTP::TOTP.new(otp_secret, issuer: issuer)
  end

  def otp_provisioning_uri
    totp.provisioning_uri(email)
  end

  def otp_qrcode_svg
    qrcode = ::RQRCode::QRCode.new(otp_provisioning_uri)
    qrcode.as_svg(module_size: 4)
  end

  def enable_otp!(code)
    return false unless consume_otp!(code.to_s)
    update!(otp_required_for_login: true)
  end

  def disable_otp!
    update!(otp_required_for_login: false, otp_secret: nil, otp_backup_codes: [])
  end

  private

  def consume_otp!(code)
    timestep = totp.verify(code, after: last_otp_timestep)
    return false if timestep.blank?

    update(consumed_timestep: timestep)
    true
  end

  def last_otp_timestep
    return consumed_timestep if consumed_timestep.present?

    0
  end

  def consume_backup_code!(code)
    return false if otp_backup_codes.blank?
    return false unless otp_backup_codes.include?(code)

    otp_backup_codes.delete(code)
    save
  end
end
