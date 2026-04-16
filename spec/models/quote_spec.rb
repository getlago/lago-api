# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quote do
  subject(:quote) { create(:quote) }

  it do
    expect(subject).to define_enum_for(:status)
      .backed_by_column_of_type(:enum)
      .with_values(
        {
          draft: "draft",
          approved: "approved",
          voided: "voided"
        }
      )
      .with_default(:draft)
      .validating(allowing_nil: false)

    expect(subject).to define_enum_for(:void_reason)
      .backed_by_column_of_type(:integer)
      .with_values(
        {
          manual: 0,
          superseded: 1,
          cascade_of_expired: 2,
          cascade_of_voided: 3
        }
      )
      .without_instance_methods
      .validating(allowing_nil: true)
  end
end
