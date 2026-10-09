# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::BillingPeriodFilters::IncrementalCombinations, cache: :memory do
  subject(:incremental_combinations) { described_class.new(cache_key: "incremental-combinations-spec") }

  let(:reads) { [] }
  let(:answers) { [] }
  let(:first_read_at) { Time.zone.parse("2026-10-09 10:00:00") }
  let(:eu_seen_at) { first_read_at - 1.hour }
  let(:us_seen_at) { first_read_at - 30.minutes }

  def fetch
    incremental_combinations.fetch do |ingested_after:|
      reads << ingested_after
      answers.shift
    end
  end

  before do
    answers << [["code", {"region" => "eu"}, eu_seen_at], ["code", {"region" => "us"}, us_seen_at]]
  end

  describe "#fetch" do
    it "reads every event of the window the first time" do
      result = travel_to(first_read_at) { fetch }

      expect(result).to eq([["code", {"region" => "eu"}, eu_seen_at], ["code", {"region" => "us"}, us_seen_at]])
      expect(reads).to eq([nil])
    end

    context "when an answer was kept" do
      let(:second_read_at) { first_read_at + 1.minute }
      let(:new_eu_seen_at) { first_read_at + 30.seconds }
      let(:apac_seen_at) { first_read_at + 40.seconds }

      before do
        travel_to(first_read_at) { fetch }

        answers << [["code", {"region" => "eu"}, new_eu_seen_at], ["code", {"region" => "apac"}, apac_seen_at]]
      end

      it "only reads the events ingested since the previous read, less the ingestion margin" do
        travel_to(second_read_at) { fetch }

        expect(reads).to eq([nil, first_read_at - described_class::INGESTION_MARGIN])
      end

      it "merges the new combinations into the kept ones, keeping the latest ingestion time" do
        result = travel_to(second_read_at) { fetch }

        expect(result).to match_array([
          ["code", {"region" => "eu"}, new_eu_seen_at],
          ["code", {"region" => "us"}, us_seen_at],
          ["code", {"region" => "apac"}, apac_seen_at]
        ])
      end

      it "starts the next read from the start of the last one" do
        travel_to(second_read_at) { fetch }
        answers << []
        travel_to(second_read_at + 1.minute) { fetch }

        expect(reads.last).to eq(second_read_at - described_class::INGESTION_MARGIN)
      end

      context "when the new read returns an older ingestion time" do
        let(:new_eu_seen_at) { eu_seen_at - 1.day }

        it "keeps the latest one" do
          result = travel_to(second_read_at) { fetch }

          expect(result).to include(["code", {"region" => "eu"}, eu_seen_at])
        end
      end

      context "without ingestion times" do
        let(:eu_seen_at) { nil }
        let(:us_seen_at) { nil }
        let(:new_eu_seen_at) { nil }
        let(:apac_seen_at) { nil }

        it "keeps one combination each" do
          result = travel_to(second_read_at) { fetch }

          expect(result).to match_array([
            ["code", {"region" => "eu"}, nil],
            ["code", {"region" => "us"}, nil],
            ["code", {"region" => "apac"}, nil]
          ])
        end
      end
    end

    context "when the full read is older than the refresh interval" do
      let(:refresh_read_at) { first_read_at + described_class::FULL_REFRESH_INTERVAL }

      before do
        travel_to(first_read_at) { fetch }

        # An incremental read keeps the entry alive without making it a full read.
        answers << []
        travel_to(first_read_at + 1.hour) { fetch }

        answers << [["code", {"region" => "us"}, us_seen_at]]
      end

      it "reads every event of the window again and drops the combinations it no longer finds" do
        result = travel_to(refresh_read_at) { fetch }

        expect(reads).to eq([nil, first_read_at - described_class::INGESTION_MARGIN, nil])
        expect(result).to eq([["code", {"region" => "us"}, us_seen_at]])
      end
    end

    context "when the answer is too large to keep" do
      before do
        stub_const("#{described_class}::MAX_COMBINATIONS", 1)

        travel_to(first_read_at) { fetch }

        answers << []
      end

      it "reads every event of the window again" do
        travel_to(first_read_at + 1.minute) { fetch }

        expect(reads).to eq([nil, nil])
      end
    end
  end
end
