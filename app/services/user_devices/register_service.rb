# frozen_string_literal: true

module UserDevices
  class RegisterService < BaseService
    Result = BaseResult

    # @option user [User] the user to match the device for
    # @option skip_log [Boolean] whether to skip logging of new device (default: false)
    def initialize(user:, skip_log: false)
      @user = user
      @skip_log = skip_log
      super
    end

    def call
      device_info = CurrentContext.device_info
      return result unless device_info

      fingerprint = Digest::SHA256.hexdigest(device_info[:user_agent])
      attributes = {
        browser: device_info[:browser],
        os: device_info[:os],
        device_type: device_info[:device_type],
        last_logged_at: Time.current,
        last_ip_address: device_info[:ip_address]
      }
      register_device(fingerprint, attributes)
      register_security_logs unless skip_log

      result
    end

    private

    attr_reader :user, :skip_log

    def register_device(fingerprint, attributes)
      device = user.user_devices.find_or_initialize_by(fingerprint:)
      @skip_log ||= !device.new_record?
      # A savepoint, so a lost insert leaves a caller's transaction usable for the re-read.
      ActiveRecord::Base.transaction(requires_new: true) { device.update!(attributes) }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      raise unless inserted_concurrently?(e)

      # Another sign-in from the same browser (a second tab) inserted the device first.
      @skip_log = true
      # The request's query cache holds the lookup above, from before that insert. The savepoint rollback clears it
      # today; reading uncached does not depend on that.
      UserDevice.uncached { user.user_devices.find_by!(fingerprint:) }.update!(attributes)
    end

    # The other insert either committed before this one's uniqueness check, or after it.
    def inserted_concurrently?(error)
      if error.is_a?(ActiveRecord::RecordInvalid)
        error.record.errors.of_kind?(:fingerprint, :taken) && error.record.errors.size == 1
      else
        violated_unique_index(error) == "index_user_devices_on_user_id_and_fingerprint"
      end
    end

    def register_security_logs
      user.active_organizations.select(&:security_logs_enabled?).each do |organization|
        Utils::SecurityLog.produce(
          organization:,
          log_type: "user",
          log_event: "user.new_device_logged_in",
          user:
        )
      end
    end
  end
end
