# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CopyToProduction::Preview do
  subject { described_class }

  it { is_expected.to have_field(:blocking_reason).of_type("CopyToProductionBlockingReasonEnum") }
  it { is_expected.to have_field(:copied_items).of_type("[CopyToProductionItem!]!") }
  it { is_expected.to have_field(:missing_parent).of_type("CopyToProductionItem") }
  it { is_expected.to have_field(:reused_items).of_type("[CopyToProductionItem!]!") }
end
