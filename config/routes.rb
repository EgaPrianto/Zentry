Rails.application.routes.draw do
  resources :sleep_entries do
    collection do
      get 'feed'
    end
  end

  # Follow/Unfollow routes
  resources :users, only: [] do
    post 'follow', to: 'follows#create'
    delete 'follow', to: 'follows#destroy'
    get 'followers', to: 'follows#followers'
    get 'following', to: 'follows#following'
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
