# frozen_string_literal: true

module Utils
  class Timezone
    def self.date_in_customer_timezone_sql(customer, value)
      sanitized_field_name = if value.is_a?(String)
        ActiveRecord::Base.sanitize_sql_for_conditions(value)
      else
        "'#{value}'"
      end
      sanitized_timezone = ActiveRecord::Base.sanitize_sql_for_conditions(customer.applicable_timezone)

      "(#{sanitized_field_name})::timestamptz AT TIME ZONE '#{sanitized_timezone}'"
    end

    def self.at_time_zone_sql(customer: 'customers', organization: 'organizations')
      <<-SQL
        ::timestamptz AT TIME ZONE COALESCE(#{customer}.timezone, #{organization}.timezone, 'UTC')
      SQL
    end
  end
end
