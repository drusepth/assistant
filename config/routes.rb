Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  get "setup" => "first_run#new", as: :setup
  post "setup" => "first_run#create"

  resources :invitations, only: %i[ create destroy ]
  get "join/:token" => "invitations#show", as: :join
  post "join/:token" => "invitations#accept"

  resources :household_members, only: %i[ update destroy ]
  resource :household, only: %i[ show update ] do
    delete :banner, to: "households#destroy_banner", as: :banner
  end

  get "welcome(/:step)" => "onboarding#show", as: :onboarding, constraints: { step: /[1-4]/ }
  patch "welcome/:step" => "onboarding#update", constraints: { step: /[1-4]/ }

  root "dashboard#show"
  get "today" => "today#show", as: :today
  get "calendar(/:year/:month)" => "calendar#show", as: :calendar,
    constraints: { year: /\d{4}/, month: /\d{1,2}/ }
  get "sections/:slug" => "sections#show", as: :section
  resources :hobbies, only: %i[ create destroy ]
  resources :groups, only: %i[ create destroy ]

  get "health/care-settings" => "care_settings#show", as: :care_settings
  patch "health/care-settings" => "care_settings#update"
  delete "health/care-settings/:kind_key" => "care_settings#destroy", as: :care_setting
  post "health/medications" => "medications#create", as: :medications
  post "health/allergies" => "allergies#create", as: :allergies
  delete "health/allergies/:id" => "allergies#destroy", as: :allergy

  post "career/win" => "career#create_win", as: :career_win
  post "career/comp_change" => "career#create_comp_change", as: :career_comp_change
  resources :job_feeds, only: %i[ create destroy ]

  resource :settings, only: %i[ show update ]
  resource :avatar, only: %i[ update destroy ]
  resource :household, only: %i[ update ]

  resources :mail, only: %i[ index show destroy ], controller: "mail" do
    member do
      post :promote
      post :remind
      post :triage
    end
  end
  # The spending ledger (D-spending-mirror): owner-only browse over the
  # mirror, quick-log, statement imports, and the taught rules.
  get "spending" => "spending#index", as: :spending
  get "spending/import" => "spending_imports#new", as: :new_spending_import
  post "spending/import" => "spending_imports#create", as: :spending_imports
  get "spending/import/mapping" => "spending_imports#mapping", as: :spending_import_mapping
  post "spending/import/mapping" => "spending_imports#apply_mapping", as: :spending_import_apply
  resources :spending_transactions, only: %i[ create update destroy ]
  resources :spending_accounts, only: %i[ create destroy ]
  resources :spending_rules, only: %i[ destroy ]
  resources :budget_categories, only: %i[ create update destroy ]

  resource :export, only: %i[ create ]
  resources :notification_channels, only: %i[ create destroy ]
  resources :reminders, only: %i[ create destroy ]
  resource :model_profile, only: %i[ update ]
  resources :access_grants, only: %i[ create destroy ]
  resources :linked_accounts, only: %i[ create update destroy ] do
    member do
      post :sync
      patch :settings, action: :update_settings
    end
  end
  resources :email_sender_rules, only: %i[ create destroy ]
  resource :mail_settings, only: %i[ update ]

  namespace :events do
    resource :import, only: %i[ new create ]
  end
  resources :events
  resources :tasks do
    # The task page's embedded chat (D30) — find-or-create the bound run,
    # append the turn.
    resource :conversation, only: %i[ show create ], module: :tasks
    member do
      patch :complete
      patch :reopen
      patch :reschedule
      patch :move
    end
  end
  resources :documents do
    member do
      post :analyze
      patch :apply_suggestion
    end
  end
  namespace :people do
    resource :import, only: %i[ new create ]
    resource :circle, only: %i[ create destroy ]
    # Group membership (D-people-circles) — a person into a People lens.
    resources :memberships, only: %i[ create destroy ], param: :section_id
  end
  resources :people do
    member do
      patch :log_contact
    end
    resource :avatar, only: %i[ destroy ], module: :people
  end
  resources :goals do
    member do
      patch :complete
      patch :reopen
      post :break_down
    end
  end
  resources :notes

  # The personal school (docs/EDUCATION_PLAN.md): the curriculum spine —
  # per-learner subjects and their topic trees (D-education-spine), the
  # commons shelf they enroll from (D-curriculum-commons), and the daily
  # review queue (D-review-scheduler).
  get "education/shelf" => "subjects#shelf", as: :curriculum_shelf
  resources :subjects do
    member do
      patch :pause
      patch :resume
      patch :finish
      post :retry_tree
    end
  end
  resources :topics, only: %i[ create update destroy ] do
    member do
      patch :mastery
      patch :move
      post :plan
    end
  end
  get "reviews" => "reviews#show", as: :reviews
  post "reviews/:id/grade" => "reviews#grade", as: :grade_review

  # The password vault (D-passwords-vault). Everything lives under
  # /credentials — the keyring cookie is path-scoped to exactly this prefix,
  # so the unlocked vault key never transits on any other request. (The
  # /passwords namespace is Rails auth's reset flow, hence the model name.)
  resources :credentials do
    member do
      post :reveal
      post :share
      delete :unshare
    end
    collection do
      post :unlock
      post :lock
      post :export
      post :recovery
      post :recovery_confirm
      post :recovery_check
      get :health
      get :import, action: :new_import
      post :import, action: :create_import
    end
  end
  scope path: "/credentials" do
    resources :emergency_contacts, only: %i[ create destroy ] do
      member do
        post :request_access
        post :deny
        get :access
        post :emergency_reveal
      end
    end
  end
  # The diary (D-diary-vault), the second sealed container. Everything lives
  # under /diary so the keyring cookie scoped to that prefix covers exactly
  # this surface — see VaultSession::COOKIES.
  resources :diary_entries, path: "diary" do
    member do
      post :share
      delete :unshare
      get :history
      post :restore
    end
    collection do
      post :unlock
      post :lock
      patch :settings
      post :export
      get :import, action: :new_import
      post :import, action: :create_import
      post :import_step
      delete :import, action: :cancel_import
    end
  end

  resource :user_password, only: :update

  resources :photos, except: :new do
    collection do
      get :map
    end
    member do
      post :ingest
      post :caption
      patch :apply_suggestion
    end
  end
  # Trips (D-trip-spine): the spine of the travel tool. Shared by
  # membership, not AccessGrant (D-trip-companions) — but everything
  # derived from photo coordinates on a trip stays owner-only under Q14.
  resources :trips do
    member do
      post :place
    end
    resources :stays, shallow: true, except: %i[ index show ]
    resources :legs, controller: "trip_legs", shallow: true, except: %i[ index show ]
    # shallow_prefix keeps the un-nested helpers namespaced (trip_comment_path,
    # not comment_path) — "comment" is too generic a name for trips to squat.
    scope shallow_prefix: "trip" do
      resources :comments, controller: "trip_comments", shallow: true, only: %i[ create destroy ]
      resources :photo_posts, controller: "trip_photo_posts", shallow: true, only: %i[ new create destroy ]
      resources :companions, controller: "trip_companions", shallow: true, only: %i[ create destroy ]
    end
  end

  resources :albums do
    member do
      post :add_photos
      delete :remove_photos
    end
  end
  resources :photo_people, only: %i[ create destroy ]

  # The recipe box (D-recipe-primitive): recipes, the books that curate
  # them, and the read-only links that carry either outside the household
  # (D-share-link — /s/:token is the only unauthenticated read path in the
  # app, and ShareLink::SHAREABLE_TYPES is what keeps it that narrow).
  resources :recipes do
    collection do
      get :import, action: :new_import
      post :import, action: :create_import
    end
    member do
      post :cook
      post :add_to_book
      delete :remove_from_book
      post :retry_import
      post :confirm_import
      post :attach_photo
    end
  end
  resources :recipe_books do
    member do
      post :add_recipes
      delete :remove_recipes
      patch :reorder
    end
  end
  resources :share_links, only: %i[ create destroy ]
  get "s/:token" => "public#show", as: :shared

  # The reader (D-feed-reader): the river of everything your feeds carried,
  # the subscriptions behind it, and the per-item verbs that make a river a
  # reader rather than a list.
  get "reader" => "reader#index", as: :reader
  post "reader/read_all" => "reader#read_all", as: :reader_read_all
  resources :feeds, except: %i[ show new ] do
    member do
      post :refresh
      # "Ask the model again" — see Feeds::Filing (D-hobby-feeds).
      post :refile
    end
    collection do
      post :refresh_all
      # The reading list leaves in the format every other reader can read.
      get :export
      post :import
      # The empty state's stocked shelf (D-hobby-feeds §7.1) — offered,
      # never subscribed.
      post :starters
    end
  end
  resources :feed_items, only: [] do
    member do
      patch :read
      patch :unread
      patch :save
      patch :unsave
    end
  end

  resources :suggestions, only: [] do
    member do
      patch :accept
      patch :dismiss
      patch :snooze
    end
  end

  # The conversation index (D-chat-index) — chat runs listed as conversations,
  # not as tool runs, which is what they are to the person having them.
  get "chats" => "chats#index", as: :chats
  get "tools/:tool_slug/run" => "tool_runs#new", as: :new_tool_run
  post "tools/:tool_slug/run" => "tool_runs#create", as: :run_tool
  resources :tool_runs, only: %i[ show destroy ] do
    resources :messages, only: %i[ index create ], controller: "tool_run_messages"
    resource :application_email, only: :create
    member do
      post :recap
      post :retry_reply
      post :save_answer
    end
  end

  namespace :admin do
    root "overview#show"
    post "datasets/refresh" => "datasets#refresh", as: :refresh_datasets
    post "datasets/import" => "datasets#import", as: :import_datasets
    resources :errors, only: :index do
      collection { delete :destroy_all }
    end
    resources :failed_jobs, only: [] do
      member do
        post :retry
        delete :discard
      end
      collection { delete :discard_all }
    end
    resource :reset, only: :create
  end

  # The install manifest. Unauthenticated on purpose: the browser fetches it
  # before anyone signs in, and it says nothing a signed-out visitor can't
  # already see. The push service worker is a static file under public/ —
  # `web_push` registers it at /service_worker.js — so only the manifest
  # needs a route.
  # The format has to be pinned: a browser fetches a manifest with
  # `Accept: */*`, which Rails resolves to :html, and the template would
  # never be found. See config/initializers/mime_types.rb.
  get "manifest.webmanifest" => "rails/pwa#manifest", as: :pwa_manifest,
    defaults: { format: :webmanifest }

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
