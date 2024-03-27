# frozen_string_literal: true

module Clickhouse
  class BaseRecord < ApplicationRecord
    self.abstract_class = true

    connects_to database: {writing: :clickhouse, reading: :clickhouse}
  end
end
