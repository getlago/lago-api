# frozen_string_literal: true

# Contract of a cursor-paginated v2 list. The including group provides:
# - `organization`
# - `paginated_path`: the list path
# - `create_paginated_record`: a lambda creating one listed record at the given `created_at`
# - `other_table_record`: optional, a record of another table whose cursor the endpoint
#   must reject, typically one rendered under the same collection name
#
# Rows already listed by the including group are tolerated: the walks are compared with
# the whole list, read in a single page.
RSpec.shared_examples "a cursor paginated v2 endpoint" do |collection:, model:|
  let(:paginated_collection) { collection }
  let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
  let(:other_table_record) do
    (model == ProductCategory) ? create(:product, organization:) : create(:product_category, organization:)
  end

  # Rows share timestamps, so that pages break on ties.
  before do
    [0, 0, 1, 1, 1, 2].each { |offset| create_paginated_record.call(created_at - offset.seconds) }
  end

  def fetch_page(params)
    get_with_token(organization, paginated_path, params)
    json
  end

  def listed_ids(params = {})
    fetch_page(params.merge(limit: 100))[paginated_collection].map { it[:lago_id] }
  end

  it "lists the rows ordered by created_at then id, both descending" do
    ids = listed_ids

    expect(ids.size).to be >= 6
    expect(model.unscoped.where(id: ids).order(created_at: :desc, id: :desc).ids).to eq(ids)
  end

  it "returns every row exactly once, walking forward then backward" do
    all_ids = listed_ids

    forward = []
    page = fetch_page(limit: 2)
    expect(page[:meta][:prev_cursor]).to be_nil
    loop do
      forward.concat(page[paginated_collection].map { it[:lago_id] })
      break unless page[:meta][:next_cursor]

      page = fetch_page(limit: 2, after: page[:meta][:next_cursor])
    end

    backward = []
    loop do
      backward.unshift(*page[paginated_collection].map { it[:lago_id] })
      break unless page[:meta][:prev_cursor]

      page = fetch_page(limit: 2, before: page[:meta][:prev_cursor])
    end

    expect(forward).to eq(all_ids)
    expect(backward).to eq(all_ids)
  end

  it "does not return a total count by default" do
    expect(fetch_page(limit: 2)[:meta].keys).to eq(%i[next_cursor prev_cursor])
  end

  it "returns the total count on the first page when asked" do
    expect(fetch_page(limit: 2, include_total_count: true)[:meta][:total_count]).to eq(listed_ids.size)
  end

  context "when the count reaches the cap" do
    before { stub_const("CursorPagination::TotalCount::MAX_COUNTED_RECORDS", 1) }

    it "flags the total count as estimated" do
      meta = fetch_page(limit: 2, include_total_count: true)[:meta]

      expect(meta[:total_count_estimated]).to be(true)
      expect(meta[:total_count]).to be >= 2
    end
  end

  it "rejects the total count on a later page" do
    next_cursor = fetch_page(limit: 2)[:meta][:next_cursor]
    fetch_page(limit: 2, after: next_cursor, include_total_count: true)

    expect(response).to have_http_status(:bad_request)
    expect(json[:code]).to eq("total_count_first_page_only")
  end

  it "rejects an out of range limit" do
    fetch_page(limit: 101)

    expect(response).to have_http_status(:bad_request)
    expect(json).to eq(
      status: 400,
      error: "Bad Request",
      code: "invalid_pagination_limit",
      error_details: {limit: {value: "101", allowed_range: "1..100"}}
    )
  end

  it "rejects the offset pagination parameters" do
    fetch_page(page: 2, per_page: 50)

    expect(response).to have_http_status(:bad_request)
    expect(json[:code]).to eq("invalid_pagination_parameter")
    expect(json[:error_details]).to eq(page: {reason: "replaced_by_cursor"}, per_page: {reason: "replaced_by_cursor"})
  end

  it "rejects a malformed cursor" do
    fetch_page(after: "not-a-cursor!")

    expect(response).to have_http_status(:bad_request)
    expect(json[:code]).to eq("invalid_pagination_cursor")
  end

  it "rejects a cursor minted for another table" do
    table = other_table_record.class.table_name
    fetch_page(after: CursorPagination::Token.encode(table:, record: other_table_record))

    expect(response).to have_http_status(:bad_request)
    expect(json[:code]).to eq("invalid_pagination_cursor")
    expect(json[:error_details]).to eq(after: {reason: "wrong_resource"})
  end
end
