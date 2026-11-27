# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CopyToProduction::Item do
  subject { described_class }

  it { is_expected.to have_field(:code).of_type("String") }
  it { is_expected.to have_field(:id).of_type("ID!") }
  it { is_expected.to have_field(:item_type).of_type("CopyToProductionItemTypeEnum!") }
  it { is_expected.to have_field(:name).of_type("String") }
end
