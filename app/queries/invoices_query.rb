# frozen_string_literal: true

# InvoicesQuery is responsible for querying invoices based on various filters.
#
# Filters available:
# - :customer_id - Filters invoices by the specified customer ID.
# - :ids - Filters invoices by an array of specified invoice IDs.
# - :status - Filters invoices by the specified status.
# - :payment_status - Filters invoices by the specified payment status.
# - :payment_dispute_lost - Filters invoices where the payment dispute has been lost.
#
# Example usage:
#   InvoicesQuery.new.call(
#     search_term: "example",
#     page: 1,
#     limit: 10,
#     filters: {
#       customer_id: 123,
#       ids: [1, 2, 3],
#       status: "finalized",
#       payment_status: "pending",
#       payment_dispute_lost: true
#     }
#   )
class InvoicesQuery < BaseQuery
  # Executes the query with the given search term, pagination, and filters.
  #
  # @param search_term [String] the term to search for in invoice attributes
  # @param page [Integer] the page number for pagination
  # @param limit [Integer] the number of invoices per page
  # @param filters [Hash] the filters to apply to the query
  # @option filters [String] :customer_id the ID of the customer to filter by
  # @option filters [Array<String>] :ids an array of invoice IDs to filter by
  # @option filters [String] :status the status of invoices to filter by
  # @option filters [String] :payment_status the payment status of invoices to filter by
  # @option filters [Boolean] :payment_dispute_lost whether to include invoices with lost payment disputes
  #
  # @return [Result] the result of the query with filtered invoices
  def call(search_term:, page:, limit:, filters: {})
    @search_term = search_term
    @customer_id = filters[:customer_id]

    invoices = base_scope.result.includes(:customer)
    invoices = invoices.where(id: filters[:ids]) if filters[:ids].present?
    invoices = invoices.where(customer_id: filters[:customer_id]) if filters[:customer_id].present?
    invoices = invoices.where(status: filters[:status]) if filters[:status].present?
    invoices = invoices.where(payment_status: filters[:payment_status]) if filters[:payment_status].present?
    invoices = invoices.where.not(payment_dispute_lost_at: nil) if filters[:payment_dispute_lost]
    invoices = invoices.order(issuing_date: :desc, created_at: :desc).page(page).per(limit)

    result.invoices = invoices
    result
  end

  private

  attr_reader :search_term

  def base_scope
    organization.invoices.not_generating.ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    terms = {
      m: 'or',
      id_cont: search_term,
      number_cont: search_term
    }
    return terms if @customer_id.present?

    terms.merge(
      customer_name_cont: search_term,
      customer_external_id_cont: search_term,
      customer_email_cont: search_term
    )
  end
end
