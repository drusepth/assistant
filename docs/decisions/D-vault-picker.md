<!-- decided -->
**D-vault-picker. The sidebar's Vault pages get a picker of their own, and onboarding asks which to switch on**


(built). The Vault group in the sidebar — Address Book, Photos, Recipes,
Documents, Notes, Mail, Passwords, Diary — was a fixed list, but not every
household wants a password manager or a diary. `/your-vault`
(`VaultPagesController`) is the twin of the Your life picker
(D-section-picker): one card per page with a blurb, an On/Off chip, and a
Turn on / Turn off button that saves right away and morphs the sidebar in
place. The door in is a "Customize" link beside the Vault heading, and a
"Choose vault pages" row appears if every page is off.

The pages are one registry, `VaultPage::ALL`, which the sidebar, the
picker, and onboarding all read — adding a page to the Vault is one row
there. The choice is stored as `users.hidden_vault_pages`, the list of
what's switched *off*, so a page added later arrives on for everyone.
Hiding a page only takes it out of the sidebar: nothing is deleted and its
URL keeps working. Mail keeps its extra condition — it appears only once an
email account is linked — and its card says so and links to Settings.

Onboarding step 1 already asked which parts of life to cover, so the vault
question joins it as a second group in the same form rather than a new
step (the flow stays four steps). A blank hidden value makes an all-unchecked
submit mean "none"; a submit without the question at all changes nothing.
