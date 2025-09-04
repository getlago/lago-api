# frozen_string_literal: true

class BaseResult
  include Result

  def self.[](*attributes)
    Class.new(BaseResult) { attr_accessor(*attributes) }
  end
end
