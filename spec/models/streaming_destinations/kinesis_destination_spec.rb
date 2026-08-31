# frozen_string_literal: true

require "rails_helper"

RSpec.describe StreamingDestinations::KinesisDestination do
  describe "#deliver_service_class" do
    it "names the kinesis delivery service" do
      expect(build(:kinesis_destination).deliver_service_class)
        .to eq(StreamingDestinations::Kinesis::DeliverService)
    end
  end

  describe "validations" do
    %i[stream_arn region role_arn].each do |setting|
      it "requires #{setting}" do
        destination = build(:kinesis_destination, setting => nil)

        expect(destination).not_to be_valid
        expect(destination.errors.where(setting, :blank)).to be_present
      end
    end

    it "does not require an external_id" do
      expect(build(:kinesis_destination, external_id: nil)).to be_valid
    end
  end

  describe "settings accessors" do
    it "round-trips through the settings column" do
      destination = create(
        :kinesis_destination,
        stream_arn: "arn:aws:kinesis:us-east-1:111122223333:stream/other",
        region: "us-east-1",
        role_arn: "arn:aws:iam::111122223333:role/Other",
        external_id: "confused-deputy-guard"
      )

      reloaded = described_class.find(destination.id)

      expect(reloaded.stream_arn).to eq("arn:aws:kinesis:us-east-1:111122223333:stream/other")
      expect(reloaded.region).to eq("us-east-1")
      expect(reloaded.role_arn).to eq("arn:aws:iam::111122223333:role/Other")
      expect(reloaded.external_id).to eq("confused-deputy-guard")
    end

    it "writes through the accessor into settings" do
      destination = build(:kinesis_destination)

      destination.region = "ap-south-1"

      expect(destination.settings["region"]).to eq("ap-south-1")
      expect(destination.region).to eq("ap-south-1")
    end

    it "keeps external_id in settings rather than secrets" do
      destination = create(:kinesis_destination, external_id: "guard")

      expect(described_class.find(destination.id).settings["external_id"]).to eq("guard")
      expect(destination.secrets).to be_nil
    end
  end
end
