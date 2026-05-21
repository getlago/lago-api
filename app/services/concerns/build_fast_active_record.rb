# frozen_string_literal: true

module BuildFastActiveRecord
  private

  # Reconstructs an AR model from a plain Hash without hitting the database.
  # Unlike new(), this skips assign_attributes (no dirty tracking, no individual setters),
  # which makes a measurable difference when rebuilding large collections of records.
  def build_fast_record(klass, attributes, new_record)
    record = klass.allocate
    record.init_with_attributes(attributes_builder_for(klass).build_from_database(attributes), new_record)
    record
  end

  def attributes_builder_for(klass)
    @attributes_builders ||= {}
    @attributes_builders[klass] ||= ActiveModel::AttributeSet::Builder.new(klass.attribute_types, klass._default_attributes)
  end
end
