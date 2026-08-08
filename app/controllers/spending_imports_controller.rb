# Statement upload → vault Document → ledger rows (MONEY.md §2.1). OFX
# imports in one step; a CSV from an account we haven't seen routes
# through the mapping form once, then the saved mapping makes every later
# import one click. The Document is the durable artifact — deleting the
# mirror loses nothing a re-import can't rebuild.
class SpendingImportsController < ApplicationController
  before_action :set_accounts

  def new
  end

  def create
    file = params[:file]
    return redirect_to new_spending_import_path, alert: "Choose a statement file first." if file.blank?

    account = resolve_account
    return redirect_to new_spending_import_path, alert: "Pick or name the account this statement is from." unless account

    content = file.read
    document = store_statement(file, account)

    if csv_needing_mapping?(file, content, account)
      redirect_to spending_import_mapping_path(document_id: document.id, account_id: account.id)
    else
      run_import(account, document, content, file.original_filename)
    end
  end

  # The one-time column-mapping step for an unfamiliar bank CSV: headers,
  # sample rows, and prefilled guesses (Spending::CsvProbe) the user confirms.
  def mapping
    @account = @accounts.find(params[:account_id])
    @document = Current.user.documents.find(params[:document_id])
    @probe = Spending::CsvProbe.new(@document.file.download)

    unless @probe.parsed?
      redirect_to new_spending_import_path, alert: "That CSV couldn't be read — re-export it from your bank and try again."
    end
  end

  def apply_mapping
    account = @accounts.find(params[:account_id])
    document = Current.user.documents.find(params[:document_id])

    mapping = params.permit(*Spending::StatementImport::MappedCsv::KEYS).to_h.compact_blank
    unless mapping["date"].present? && mapping["description"].present? &&
           (mapping["amount"].present? || mapping["debit"].present? || mapping["credit"].present?)
      return redirect_to spending_import_mapping_path(document_id: document.id, account_id: account.id),
        alert: "Pick at least the date, description, and an amount column."
    end

    account.update!(csv_mapping: mapping)
    run_import(account, document, document.file.download, document.title)
  end

  private
    def set_accounts
      @accounts = Current.user.spending_accounts.order(:created_at)
    end

    # The form offers existing accounts plus inline creation — naming the
    # account is part of the first import, not a separate chore.
    def resolve_account
      if params[:spending_account_id].present?
        @accounts.find(params[:spending_account_id])
      elsif params[:new_account_name].present?
        Current.user.spending_accounts.create!(
          name: params[:new_account_name],
          kind: params[:new_account_kind].presence_in(SpendingAccount::KINDS) || "checking")
      end
    end

    def store_statement(file, account)
      document = Current.user.documents.create!(
        title: "#{account.name} statement — #{file.original_filename}")
      document.file.attach(file)
      document.sections = [ Section.find_by(slug: "money") ].compact
      document
    end

    def csv_needing_mapping?(file, content, account)
      !Spending::StatementImport::Ofx.handles?(file.original_filename, content) &&
        Spending::StatementImport::MappedCsv.handles?(file.original_filename, content) &&
        account.csv_mapping.blank?
    end

    def run_import(account, document, content, filename)
      result = Spending::StatementImport.new(
        user: Current.user, account: account, content: content,
        filename: filename, document_id: document.id).call

      if result.error == :mapping_needed
        redirect_to spending_import_mapping_path(document_id: document.id, account_id: account.id)
      elsif result.error
        redirect_to new_spending_import_path, alert: result.error
      else
        redirect_to spending_path,
          notice: "Imported #{result.imported} #{"transaction".pluralize(result.imported)}" \
                  "#{result.skipped.positive? ? " (#{result.skipped} already known)" : ""}."
      end
    end
end
