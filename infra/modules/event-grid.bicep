// ============================================================
// Event Grid Module
// Subscription-level Event Grid subscription for RG write events.
// Routes to the Auto-Budget Logic App.
// ============================================================

targetScope = 'subscription'

param logicAppCallbackUrl string
param eventSubscriptionName string = 'finops-rg-write-events'

resource eventSubscription 'Microsoft.EventGrid/eventSubscriptions@2024-06-01-preview' = {
  name: eventSubscriptionName
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: logicAppCallbackUrl
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Resources.ResourceWriteSuccess'
      ]
      advancedFilters: [
        {
          operatorType: 'StringContains'
          key: 'subject'
          values: [ '/resourceGroups/' ]
        }
        {
          operatorType: 'StringNotContains'
          key: 'subject'
          values: [ '/providers/' ]  // RG-level events only, not resource-level
        }
      ]
    }
    eventDeliverySchema: 'EventGridSchema'
  }
}

output eventSubscriptionId string = eventSubscription.id
