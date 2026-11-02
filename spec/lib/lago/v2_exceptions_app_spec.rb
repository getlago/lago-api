# frozen_string_literal: true

require "rails_helper"

RSpec.describe Lago::V2ExceptionsApp do
  subject(:answer) { described_class.new(fallback).call(env) }

  let(:fallback) { ->(_env) { [418, {}, ["fallback"]] } }
  let(:env) { {"PATH_INFO" => "/#{status}", "action_dispatch.original_path" => path, "action_controller.instance" => controller} }
  let(:status) { 500 }
  let(:path) { "/api/v2/taxes" }
  let(:controller) { Api::V2::TaxesController.new }
  let(:v2_headers) { {"content-type" => "application/json; charset=utf-8", "x-lago-endpoint-status" => "beta"} }

  it "renders the v2 body named after the status for a native v2 controller" do
    expect(answer).to eq([500, v2_headers, ['{"code":"internal_server_error","details":[]}']])
  end

  context "with a malformed request" do
    let(:status) { 400 }

    it { expect(answer).to eq([400, v2_headers, ['{"code":"bad_request","details":[]}']]) }
  end

  context "with a 404" do
    let(:status) { 404 }

    it { expect(answer).to eq([404, v2_headers, ['{"code":"resource_not_found","details":[]}']]) }
  end

  # Rack renamed this reason phrase in 3.1; the code stays Lago's.
  context "with a 422" do
    let(:status) { 422 }

    it { expect(answer).to eq([422, v2_headers, ['{"code":"unprocessable_content","details":[]}']]) }
  end

  context "with a client error outside the table" do
    let(:status) { 418 }

    it { expect(answer).to eq([418, v2_headers, ['{"code":"bad_request","details":[]}']]) }
  end

  context "when the unknown route controller handled the request" do
    let(:controller) { Api::UnknownV2RoutesController.new }

    it { expect(answer).to eq([500, v2_headers, ['{"code":"internal_server_error","details":[]}']]) }
  end

  context "when a v1 controller handled a shared /api/v2 route" do
    let(:path) { "/api/v2/billable_metrics" }
    let(:controller) { Api::V1::BillableMetricsController.new }

    it { expect(answer).to eq([418, {}, ["fallback"]]) }
  end

  context "when no controller handled a request under /api/v2" do
    let(:controller) { nil }

    it { expect(answer).to eq([500, v2_headers, ['{"code":"internal_server_error","details":[]}']]) }

    context "with the bare /api/v2" do
      let(:path) { "/api/v2" }

      it { expect(answer).to eq([500, v2_headers, ['{"code":"internal_server_error","details":[]}']]) }
    end
  end

  context "when no controller handled a request outside /api/v2" do
    let(:path) { "/api/v1/taxes" }
    let(:controller) { nil }

    it { expect(answer).to eq([418, {}, ["fallback"]]) }
  end
end
