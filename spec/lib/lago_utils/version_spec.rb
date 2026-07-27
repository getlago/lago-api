# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoUtils::Version do
  describe ".call" do
    subject(:result) { described_class.call(default: "test-default") }

    let(:version_file) { Rails.root.join("LAGO_VERSION") }

    context "when the file contains a git commit SHA" do
      let(:sha) { "0f425aee1b9e7c927eb9559055fd1d11708bc7b5" }
      let(:release_date) { Date.new(2026, 7, 24) }

      before do
        allow(File).to receive(:read).with(version_file).and_return("#{sha}\n")
        allow(File).to receive(:ctime).with(version_file).and_return(release_date.to_time)
      end

      it "returns the release date as the number" do
        expect(result.number).to eq(release_date.iso8601)
      end

      it "returns the SHA" do
        expect(result.sha).to eq(sha)
      end

      it "returns the github url pointing at the SHA" do
        expect(result.github_url).to eq("https://github.com/getlago/lago-api/tree/#{sha}")
      end

      it "returns the SHA as the sha_or_number" do
        expect(result.sha_or_number).to eq(sha)
      end
    end

    context "when the file contains a version tag" do
      before do
        allow(File).to receive(:read).with(version_file).and_return("v1.20.0\n")
      end

      it "returns the tag as the number" do
        expect(result.number).to eq("v1.20.0")
      end

      it "returns a nil SHA" do
        expect(result.sha).to be_nil
      end

      it "returns the github url pointing at the tag" do
        expect(result.github_url).to eq("https://github.com/getlago/lago-api/tree/v1.20.0")
      end

      it "returns the tag as the sha_or_number" do
        expect(result.sha_or_number).to eq("v1.20.0")
      end
    end

    context "when the file cannot be read" do
      before do
        allow(File).to receive(:read).with(version_file).and_raise(Errno::ENOENT)
      end

      it "returns the default as the number" do
        expect(result.number).to eq("test-default")
      end

      it "returns a nil SHA" do
        expect(result.sha).to be_nil
      end

      it "returns the base github url" do
        expect(result.github_url).to eq("https://github.com/getlago/lago-api")
      end

      it "returns the default as the sha_or_number" do
        expect(result.sha_or_number).to eq("test-default")
      end
    end
  end
end
