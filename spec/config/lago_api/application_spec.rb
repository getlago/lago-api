# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoApi::Application do
  describe ".origin_of" do
    it "drops the path and the default port" do
      expect(described_class.origin_of("https://app.getlago.com/")).to eq("https://app.getlago.com")
      expect(described_class.origin_of("https://app.getlago.com:443/customers")).to eq("https://app.getlago.com")
    end

    it "keeps a custom port" do
      expect(described_class.origin_of("http://localhost:8080")).to eq("http://localhost:8080")
    end

    it "lowercases the host as browsers do" do
      expect(described_class.origin_of("https://App.GetLago.com")).to eq("https://app.getlago.com")
    end
  end
end
