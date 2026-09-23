# Numbers saved before PhoneNumber existed were stored as typed. Bring the
# ones it can read into the stored shape; the rest stay exactly as they are,
# which is what PhoneNumber.normalize returns for them anyway.
class NormalizePhoneNumbers < ActiveRecord::Migration[8.1]
  def up
    %w[ people households ].each do |table|
      select_rows("SELECT id, phone FROM #{table} WHERE phone IS NOT NULL").each do |id, phone|
        normalized = PhoneNumber.normalize(phone)
        next if normalized == phone

        execute "UPDATE #{table} SET phone = #{connection.quote(normalized)} WHERE id = #{connection.quote(id)}"
      end
    end
  end

  def down
    # Irreversible in content but harmless in shape: E.164 is a phone
    # number every earlier version of the app could already store.
  end
end
