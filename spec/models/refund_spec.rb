# frozen_string_literal: true

require "rails_helper"

RSpec.describe Refund do
  subject(:refund) { build(:refund) }

  describe "associations" do
    it { is_expected.to belong_to(:organization) }
  end
end
