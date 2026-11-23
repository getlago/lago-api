# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CopyToProduction::CopyInput do
  subject { described_class }

  it { is_expected.to accept_argument(:id).of_type("ID!") }
  it { is_expected.to accept_argument(:item_type).of_type("CopyToProductionCopyableItemTypeEnum!") }
end
