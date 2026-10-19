# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoApi::Application do
  describe "#lago_front_origin" do
    subject(:lago_front_origin) { Rails.application.lago_front_origin }

    before { allow(Rails.application.config).to receive(:lago_front_url).and_return(lago_front_url) }

    context "with the default port" do
      let(:lago_front_url) { "https://app.getlago.com/" }

      it { is_expected.to eq("https://app.getlago.com") }
    end

    context "with an explicit default port and a path" do
      let(:lago_front_url) { "https://app.getlago.com:443/customers" }

      it { is_expected.to eq("https://app.getlago.com") }
    end

    context "with a custom port" do
      let(:lago_front_url) { "http://localhost:8080" }

      it { is_expected.to eq("http://localhost:8080") }
    end

    context "with an uppercase host" do
      let(:lago_front_url) { "https://App.GetLago.com" }

      it { is_expected.to eq("https://app.getlago.com") }
    end
  end
end
