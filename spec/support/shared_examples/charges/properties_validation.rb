# frozen_string_literal: true

RSpec.shared_examples 'grouped_by property validation' do
  let(:grouped_by) { [] }

  it { expect(validation_service).to be_valid }

  context "when attribute is not an array" do
    let(:grouped_by) { "group" }

    it "is invalid" do
      expect(validation_service).not_to be_valid
      expect(validation_service.result.error).to be_a(BaseService::ValidationFailure)
      expect(validation_service.result.error.messages.keys).to include(:grouped_by)
      expect(validation_service.result.error.messages[:grouped_by]).to include("invalid_type")
    end
  end

  context "when attribute is not a list of string" do
    let(:grouped_by) { [12, 45] }

    it "is invalid" do
      expect(validation_service).not_to be_valid
      expect(validation_service.result.error).to be_a(BaseService::ValidationFailure)
      expect(validation_service.result.error.messages.keys).to include(:grouped_by)
      expect(validation_service.result.error.messages[:grouped_by]).to include("invalid_type")
    end
  end

  context "when attribute is an empty string" do
    let(:grouped_by) { "" }

    it "is invalid" do
      expect(validation_service).not_to be_valid
      expect(validation_service.result.error).to be_a(BaseService::ValidationFailure)
      expect(validation_service.result.error.messages.keys).to include(:grouped_by)
      expect(validation_service.result.error.messages[:grouped_by]).to include("invalid_type")
    end
  end
end
