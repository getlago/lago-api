# frozen_string_literal: true

class ModelSerializer
  attr_reader :model, :options

  def initialize(model, options = {})
    @model = model
    @options = options
  end

  def serialize
    {id: model.id}
  end

  def to_json(options = {})
    {
      root_name => serialize
    }.to_json(options)
  end

  def root_name
    options.fetch(:root_name, :data)
  end

  def include?(value)
    return false if options[:includes].blank?

    options[:includes].include?(value)
  end
end
