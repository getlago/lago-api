# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::UsageAttributionTypesQueryFiltersContract do
  subject(:result) { described_class.new.call(filters.to_h) }

  let(:filters) { {} }

  it "is valid without any filter" do
    expect(result.success?).to be(true)
  end

  context "when filtering by role" do
    UsageAttributionType::ROLES.each_value do |role|
      context "when the role is #{role}" do
        let(:filters) { {role:} }

        it "is valid" do
          expect(result.success?).to be(true)
        end
      end
    end

    context "when the role is nil" do
      let(:filters) { {role: nil} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
    end

    context "when the role is an empty string" do
      let(:filters) { {role: ""} }

      it "is valid and coerces the role to nil" do
        expect(result.success?).to be(true)
        expect(result.to_h[:role]).to be_nil
      end
    end

    context "when the role is not a known role" do
      let(:filters) { {role: "bogus"} }

      it "is invalid" do
        expect(result.success?).to be(false)
        expect(result.errors.to_h).to eq({role: ["must be one of: hierarchical, flat"]})
      end
    end

    context "when the role is an array" do
      let(:filters) { {role: ["flat"]} }

      it "is invalid" do
        expect(result.success?).to be(false)
        expect(result.errors.to_h).to eq({role: ["must be a string"]})
      end
    end
  end
end
