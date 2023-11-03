# frozen_string_literal: true

module Analytics
  class Base < ApplicationRecord
    self.abstract_class = true

    def self.find_all_by(organization_id, **args)
      sql = query(organization_id, **args)

      result = ActiveRecord::Base.connection.exec_query(sql)
      result.to_a
    end
  end
end
