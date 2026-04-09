# frozen_string_literal: true

RSpec.shared_examples "presentation_group_keys property validation" do
  let(:grouping_properties) { {"presentation_group_keys" => presentation_group_keys} }
  let(:presentation_group_keys) { {} }

  it { expect(validation_service).to be_valid }

  context "when presentation_group_keys is nil" do
    let(:presentation_group_keys) { nil }

    it "is valid" do
      expect(validation_service).to be_valid
    end
  end

  context "when presentation_group_keys is an empty array" do
    let(:presentation_group_keys) { [] }

    it "is valid" do
      expect(validation_service).to be_valid
    end
  end

  context "when presentation_group_keys is valid with 1 element" do
    let(:presentation_group_keys) { [{"value" => "region"}] }

    it "is valid" do
      expect(validation_service).to be_valid
    end
  end

  context "when presentation_group_keys is valid with 2 elements" do
    let(:presentation_group_keys) { [{"value" => "region"}, {"value" => "country"}] }

    it "is valid" do
      expect(validation_service).to be_valid
    end
  end

  context "when presentation_group_keys has options" do
    let(:presentation_group_keys) do
      [
        {"value" => "region", "options" => {"display_in_invoice" => true}},
        {"value" => "country", "options" => {"display_in_invoice" => false}}
      ]
    end

    it "is valid" do
      expect(validation_service).to be_valid
    end
  end

  context "when presentation_group_keys has more than 2 elements" do
    let(:presentation_group_keys) do
      [
        {"value" => "region"},
        {"value" => "country"},
        {"value" => "city"}
      ]
    end

    it "is invalid" do
      expect(validation_service).not_to be_valid
      expect(validation_service.result.error).to be_a(BaseService::ValidationFailure)
      expect(validation_service.result.error.messages.keys).to include(:presentation_group_keys)
      expect(validation_service.result.error.messages[:presentation_group_keys]).to include("presentation_group_keys have a maximum of 2 elements")
    end
  end

  context "when presentation_group_keys is not an array" do
    let(:presentation_group_keys) { "not_an_array" }

    it "is invalid" do
      expect(validation_service).not_to be_valid
      expect(validation_service.result.error).to be_a(BaseService::ValidationFailure)
      expect(validation_service.result.error.messages.keys).to include(:presentation_group_keys)
      expect(validation_service.result.error.messages[:presentation_group_keys]).to include("presentation_group_keys must be an array of hashes with a 'value' key")
    end
  end

  context "when presentation_group_keys contains non-hash elements" do
    let(:presentation_group_keys) { ["region", "country"] }

    it "is invalid" do
      expect(validation_service).not_to be_valid
      expect(validation_service.result.error).to be_a(BaseService::ValidationFailure)
      expect(validation_service.result.error.messages.keys).to include(:presentation_group_keys)
      expect(validation_service.result.error.messages[:presentation_group_keys]).to include("presentation_group_keys must be an array of hashes with a 'value' key")
    end
  end

  context "when presentation_group_keys contains hashes without 'value' key" do
    let(:presentation_group_keys) { [{"key" => "region"}, {"value" => "country"}] }

    it "is invalid" do
      expect(validation_service).not_to be_valid
      expect(validation_service.result.error).to be_a(BaseService::ValidationFailure)
      expect(validation_service.result.error.messages.keys).to include(:presentation_group_keys)
      expect(validation_service.result.error.messages[:presentation_group_keys]).to include("presentation_group_keys must be an array of hashes with a 'value' key")
    end
  end
end
