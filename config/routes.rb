Rails.application.routes.draw do

  scope :admin, as: 'admin', module: 'the_sync_admin' do
    resources :sync_audits do
      post :sync, on: :collection
      patch :apply, on: :member
    end
  end

end
