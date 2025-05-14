# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # NOTE: This fake column will force Rails to explicitly list columns in SELECT queries
  #       instead of using `SELECT *`, which prevent theActiveRecord::PreparedStatementCacheExpired error on deploy
  #       See: https://github.com/getlago/lago-api/pull/3640
  self.ignored_columns += %i[__force_column_list__]
end
