patlite-api
===

WebAPI server to control [Patlite NH Series](http://www.patlite.jp/product/nh-spl.html)  
Supports [Mackerel](mackerel.io) Webhook


1. Requirement
  - Ruby
  - [bundler gem](http://bundler.io/)
  
2. Installation
  1. clone this repository
  2. `$ cd patlite-api`
  3. `$ bundle`
  4. Edit Patlite `host` and `ruser` in `app.rb`
    1. `set :patlite_host,  "EDIT_HERE"
    2. `set :patlite_ruser, "EDIT_HERE"`
    3. `protected!("EDIT_HERE", "EDIT_HERE")` if you want to use Webhook of [Mackerel](mackerel.io)

3. Run
`bundle exec rackup`

4. How to use?
  1. Read API Document (Access to `/`)
  2. Set Webhook to `http://USER:PASSWORD@HOST_IP/webhook` in [Mackerel](mackerel.io)

5. Lisence
MIT