#
# Cookbook Name:: hipsnip-mongodb
# Recipe:: replica_set
#
# Copyright 2013, HipSnip Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require 'pry'
include_recipe "hipsnip-mongodb::default"
if Chef::Config[:solo]
  raise "Sorry - this recipe is for Chef Server only"
end

::Chef::Recipe.send(:include, ::HipSnip::MongoDB::Helpers)

include_recipe "hipsnip-mongodb::default"
replica_set_name = node['mongodb']['mongod']['replicaSet']
Chef::Log.info "Found node associated to #{replica_set_name} in environment #{node.chef_environment}"
hipsnip_mongodb_mongod "default" do
  port node['mongodb']['mongod']['port']
  bind_ip node['mongodb']['mongod']['bind_ip'] unless node['mongodb']['mongod']['bind_ip'].empty?
  replica_set replica_set_name
end


############################
# Look for existing nodes

Chef::Log.info "Looking for Replica Set nodes..."
replica_set_nodes = search("node", "mongodb_mongod_replicaSet:#{replica_set_name}")|| []
Chef::Log.info "#{replica_set_nodes.length} node(s) found"

Chef::Log.info "Generating member configuration for nodes" unless replica_set_nodes.empty?
replica_set_members = replica_set_nodes.collect do |replica_set_node|
  # only add ones with a member_id already set
  if replica_set_node['mongodb']['mongod']['member_id']
    member_from_node(replica_set_node)
  else
    Chef::Log.warn "Node '#{node.name}' doesn't have a member_id - ignoring"
    nil
  end
end
binding.pry
Chef::Log.info "Replica Set Members #{replica_set_members}"
replica_set_members = replica_set_members.compact # Remove the nils
binding.pry
Chef::Log.info "Replica Set Members #{replica_set_members}"

############################
# Member_id for this node

if node['mongodb']['mongod']['member_id']
  # Replace the stored details for this member node
  # Works around incomplete nodes being returned by search in Chef 11
  unless replica_set_members.select{|m| m['id'] == node['mongodb']['mongod']['member_id']}.empty?
    replica_set_members.reject!{|m| m['id'] == node['mongodb']['mongod']['member_id']}
    replica_set_members << member_from_node(node)
  end
else
  Chef::Log.info "This node doesn't seem to have a member_id - setting one now"

  
  member_id = Proc.new do |rs| 
    if rs.empty? then  0
    else 
      max_id_node = rs.max_by{|m| m['id'] == nil  ? -1: m['id']} 
      if (max_id_node.nil?)
        0
      else 
        max_id_node['id'] + 1
      end
    end
  end.call(replica_set_members)

  Chef::Log.info "Setting '#{member_id}' as new member_id for node"
  node.set['mongodb']['mongod']['member_id'] = member_id

  replica_set_members << member_from_node(node)
end



hipsnip_mongodb_replica_set node['mongodb']['mongod']['replicaSet'] do
  members replica_set_members
end
