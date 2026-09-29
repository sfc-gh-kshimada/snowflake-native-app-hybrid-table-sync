-- Provider account: set release directive and publish a PRIVATE listing to specific consumer accounts
USE ROLE ACCOUNTADMIN;

-- if the package has release channels enabled
ALTER APPLICATION PACKAGE DEMO_HT_PKG MODIFY RELEASE CHANNEL DEFAULT ADD VERSION V1;
ALTER APPLICATION PACKAGE DEMO_HT_PKG MODIFY RELEASE CHANNEL DEFAULT SET DEFAULT RELEASE DIRECTIVE VERSION = V1 PATCH = 0;
-- (without release channels) ALTER APPLICATION PACKAGE DEMO_HT_PKG SET DEFAULT RELEASE DIRECTIVE VERSION = V1 PATCH = 0;

-- targets.accounts => private listing (not on the public Marketplace)
CREATE EXTERNAL LISTING IF NOT EXISTS DEMO_HT_LISTING APPLICATION PACKAGE DEMO_HT_PKG AS $$
title: "Demo Hybrid Lookup PoC"
subtitle: "Shared table to hybrid table sync"
description: "PoC: sync provider data into an app-owned hybrid table, query directly or via Cortex Agents"
listing_terms:
  type: "OFFLINE"
targets:
  accounts: ["<CONSUMER_ORG>.<CONSUMER_ACCOUNT>"]
$$ PUBLISH = TRUE;

SHOW LISTINGS LIKE 'DEMO_HT_LISTING';   -- note global_name for the consumer
