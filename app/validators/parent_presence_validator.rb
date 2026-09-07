# frozen_string_literal: true

# Validates that a record references exactly one — or, with `optional: true`, at
# most one — of the named parent associations. A parent counts as present when
# either its foreign key or a built (unsaved) association is set, so it holds
# both for a persisted parent scoped out of a default scope and for a
# `build(...)` association.
#
#   validates_with ParentPresenceValidator,
#     parents: %i[plan catalog_plan],
#     error: :exactly_one_plan_required
class ParentPresenceValidator < ActiveModel::Validator
  def validate(record)
    present = options.fetch(:parents).count { |name| parent_present?(record, name) }
    return if present == 1
    return if present.zero? && options[:optional]

    record.errors.add(:base, options.fetch(:error))
  end

  private

  def parent_present?(record, name)
    record.public_send(:"#{name}_id").present? || record.public_send(name).present?
  end
end
