# frozen_string_literal: true

module Metrics
  class Base < ApplicationRecord
    self.abstract_class = true

    def self.find_all_by(organization_id, **args)
      sql = sanitize_sql([query.squish, { organization_id: }.merge(args)])

      ActiveRecord::Base.structs_from_sql(columns, sql)
    end
  end
end
