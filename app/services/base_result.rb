# frozen_string_literal: true

class BaseResult
  include Result

  class_attribute :exposed_attributes, default: [] # rubocop:disable ThreadSafety/ClassAndModuleAttributes

  def self.[](*attributes)
    Class.new(BaseResult) do
      attr_accessor(*attributes)

      self.exposed_attributes = attributes
    end
  end

  def ==(other)
    return false unless other.class == self.class
    return false unless failure? == other.failure?

    self.class.exposed_attributes.all? do |attribute|
      send(attribute) == other.send(attribute)
    end
  end
end
