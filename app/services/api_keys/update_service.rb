# frozen_string_literal: true

module ApiKeys
  class UpdateService < BaseService
    Result = BaseResult[:api_key]

    def initialize(api_key:, params:)
      @api_key = api_key
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: "api_key") unless api_key

      if params[:permissions].present? && !api_key.organization.api_permissions_enabled?
        return result.forbidden_failure!(code: "premium_integration_missing")
      end

      api_key.update!(params.slice(:name, :permissions))
      ApiKeys::CacheService.expire_cache(api_key.value)

      register_security_log

      result.api_key = api_key
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :api_key, :params

    def register_security_log
      diff = {
        name: deep_diff("name"),
        permissions: deep_diff("permissions")
      }.compact_blank

      Utils::SecurityLog.produce(
        organization: api_key.organization,
        log_type: "api_key",
        log_event: "api_key.updated",
        resources: {
          name: api_key.name,
          value_ending: api_key.value.last(4),
          **diff
        }
      )
    end

    def deep_diff(key)
      diff_values(*api_key.previous_changes[key]) if api_key.previous_changes.key?(key)
    end

    def diff_values(old_val, new_val)
      case new_val
      when Hash
        new_val.each_with_object({}) do |(k, v), h|
          next if old_val[k] == v
          sub = diff_values(old_val[k], v)
          h[k.to_sym] = sub if sub
        end
      when Array
        {deleted: (old_val - new_val), added: (new_val - old_val)}.compact_blank
      else
        {deleted: old_val, added: new_val}.compact_blank
      end
    end
  end
end
