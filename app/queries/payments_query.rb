# frozen_string_literal: true

class PaymentsQuery < BaseQuery
  Result = BaseResult[:payments]
  Filters = BaseFilters[:invoice_id, :external_customer_id]

  def call
    return result unless validate_filters.success?

    payments = base_scope.result
    payments = apply_filters(payments)
    payments = paginate(payments)
    payments = apply_consistent_ordering(payments)

    result.payments = payments
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::PaymentsQueryFiltersContract.new
  end

  def base_scope
    Payment.where.not(customer_id: nil)
      .for_organization(organization)
      .ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    terms = {
      m: "or",
      id_cont: search_term,
      provider_payment_id_cont: search_term,
      reference_cont: search_term
    }

    # Add payable search terms if not filtering by specific invoice
    if filters.invoice_id.blank?
      terms[:invoice_number_cont] = search_term
    end

    # Add customer search terms if not filtering by specific customer
    if filters.external_customer_id.blank?
      terms.merge!(
        customer_name_cont: search_term,
        customer_firstname_cont: search_term,
        customer_lastname_cont: search_term,
        customer_external_id_cont: search_term,
        customer_email_cont: search_term
      )
    end

    terms
  end

  def apply_filters(scope)
    scope = filter_by_invoice(scope) if filters.invoice_id.present?
    scope = filter_by_customer(scope) if filters.external_customer_id.present?
    scope
  end

  def filter_by_customer(scope)
    external_customer_id = filters.external_customer_id

    scope.joins(:customer).where("customers.external_id = :external_customer_id", external_customer_id:)
  end

  def filter_by_invoice(scope)
    invoice_id = filters.invoice_id

    scope.joins("LEFT JOIN invoices_payment_requests ON invoices_payment_requests.payment_request_id = payments.payable_id")
      .where("invoices.id = :invoice_id OR invoices_payment_requests.invoice_id = :invoice_id", invoice_id:)
  end
end
