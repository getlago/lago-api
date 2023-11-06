# frozen_string_literal: true

module Analytics
  class Base < ApplicationRecord
    self.abstract_class = true

    def self.find_all_by(organization_id, **args)
      Rails.cache.fetch(cache_key(organization_id, **args), expires_in: cache_expiration) do
        sql = query(organization_id, **args)

        result = ActiveRecord::Base.connection.exec_query(sql)
        result.to_a
      end
    end

    def self.cache_expiration
      48.hours
    end
  end
end
