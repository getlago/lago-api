# frozen_string_literal: true

require "rails_helper"

RSpec.describe PresentationBreakdown do
  subject { build(:presentation_breakdown) }

  describe "associations" do
    it do
      is_expected.to belong_to(:organization)
      is_expected.to belong_to(:fee)
    end
  end
end
