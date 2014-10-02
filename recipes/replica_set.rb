#
# Cookbook Name:: hipsnip-mongodb
# Recipe:: replicaSet
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

if Chef::Config[:solo]
  raise "Sorry - this recipe is for Chef Server only"
end

::Chef::Recipe.send(:include, ::HipSnip::MongoDB::Helpers)

include_recipe "hipsnip-mongodb::default"
replicaSetName = node['mongodb']['mongod']['replicaSet']

hipsnip_mongodb_mongod "default" do
  port node['mongodb']['mongod']['port']
  bind_ip node['mongodb']['mongod']['bind_ip'] unless node['mongodb']['mongod']['bind_ip'].empty?
  replicaSet replicaSetName
end


############################
# Look for existing nodes

Chef::Log.info "Looking for Replica Set nodes..."
replicaSetNodes = search("node", "mongodb_mongod_replicaSet:#{replicaSetName} AND chef_environment:#{node.chef_environment}") || []
Chef::Log.info "#{replicaSetNodes.length} node(s) found"

Chef::Log.info "Generating member configuration for nodes" unless replicaSetNodes.empty?
replicaSetMembers = replicaSetNodes.collect do |replicaSetNode|
  # only add ones with a member_id already set
  if replicaSetNode['mongodb']['mongod']['member_id']
    member_from_node(replicaSetNode)
  else
    Chef::Log.warn "Node '#{node.name}' doesn't have a member_id - ignoring"
  end
end


############################
# Member_id for this node

if node['mongodb']['mongod']['member_id']
  # Replace the stored details for this member node
  # Works around incomplete nodes being returned by search in Chef 11
  unless replicaSetMembers.select{|m| m['id'] == node['mongodb']['mongod']['member_id']}.empty?
    replicaSetMembers.reject!{|m| m['id'] == node['mongodb']['mongod']['member_id']}
    replicaSetMembers << member_from_node(node)
  end
else
  Chef::Log.info "This node doesn't seem to have a member_id - setting one now"

  member_id = if replicaSetMembers.empty? then 0
              else replicaSetMembers.max_by{|m| m['id']}['id'] + 1
              end

  Chef::Log.info "Setting '#{member_id}' as new member_id for node"
  node.set['mongodb']['mongod']['member_id'] = member_id

  replicaSetMembers << member_from_node(node)
end


hipsnip_mongodb_replica_set node['mongodb']['mongod']['replicaSet'] do
  members replicaSetMembers
end
