# frozen_string_literal: true

return unless defined? HttpLog

HttpLog.configure do |config|
  config.enabled = true
  config.color = :yellow

  # The reCAPTCHA siteverify body carries the secret.
  config.url_denylist_pattern = %r{clickhouse:8123|recaptcha/api/siteverify}
end
