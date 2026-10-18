// The canonical callable registry.
//
// Each row is one Cloud Function callable: which service handles it, which
// method runs, whether the caller must be an authenticated operator, and which
// callable options apply. Both the Cloud Functions adapter (src/index.js) and
// the HTTP adapter (server/http_adapter.js) are generated from this list, so
// the two runtimes cannot drift.
//
// Derived once from the original src/index.js. Only two argument shapes are
// expressible here:
//   mode "resident"  ->  service.method(data)
//   mode "operator"  ->  service.method({ operatorUid, signInProvider }, data)
// A callable that does anything else (picking fields off data, reshaping its
// return, branching on auth) is hand-written in src/app.js under
// customCallables. Those are: createResidentSession, validateResidentSession,
// revokeResidentSession, listApprovedTaskTemplates, getLastValidWeatherSnapshot.
module.exports = [
  { name: "getEmergencyDirectory", service: "emergencyDirectory", method: "getEmergencyDirectory", mode: "resident", options: "callableOptions" },
  { name: "createTaskDraft", service: "tasks", method: "createDraft", mode: "operator", options: "callableOptions" },
  { name: "activateTaskCampaign", service: "tasks", method: "activateCampaign", mode: "operator", options: "callableOptions" },
  { name: "listActiveTaskCampaigns", service: "tasks", method: "listActiveTaskCampaigns", mode: "operator", options: "callableOptions" },
  { name: "listRtTaskHistory", service: "tasks", method: "listRtTaskHistory", mode: "operator", options: "callableOptions" },
  { name: "listTaskLifecycleEvents", service: "tasks", method: "listTaskLifecycleEvents", mode: "operator", options: "callableOptions" },
  { name: "listWeatherSuggestions", service: "weatherSuggestions", method: "listWeatherSuggestions", mode: "operator", options: "callableOptions" },
  { name: "ignoreWeatherSuggestion", service: "weatherSuggestions", method: "ignoreWeatherSuggestion", mode: "operator", options: "callableOptions" },
  { name: "closeTaskCampaign", service: "tasks", method: "closeTaskCampaign", mode: "operator", options: "callableOptions" },
  { name: "cancelTaskCampaign", service: "tasks", method: "cancelTaskCampaign", mode: "operator", options: "callableOptions" },
  { name: "listResidentActiveTasks", service: "taskResponses", method: "listResidentActiveTasks", mode: "resident", options: "callableOptions" },
  { name: "recordResidentTaskResponse", service: "taskResponses", method: "recordResidentTaskResponse", mode: "resident", options: "callableOptions" },
  { name: "submitTaskCompletion", service: "taskResponses", method: "submitTaskCompletion", mode: "resident", options: "callableOptions" },
  { name: "uploadResidentTaskEvidence", service: "taskEvidence", method: "uploadResidentEvidence", mode: "resident", options: "evidenceUploadOptions" },
  { name: "deleteResidentTaskEvidence", service: "taskEvidence", method: "deleteResidentEvidence", mode: "resident", options: "callableOptions" },
  { name: "getTaskEvidenceForVerification", service: "taskEvidence", method: "getEvidenceForOperator", mode: "operator", options: "callableOptions" },
  { name: "listPendingTaskVerifications", service: "taskResponses", method: "listPendingTaskVerifications", mode: "operator", options: "callableOptions" },
  { name: "verifyTaskCompletion", service: "taskResponses", method: "verifyTaskCompletion", mode: "operator", options: "callableOptions" },
  { name: "getTaskResponseRecap", service: "taskResponses", method: "getTaskResponseRecap", mode: "operator", options: "callableOptions" },
  { name: "createProxyResident", service: "proxyResidents", method: "createProxyResident", mode: "operator", options: "callableOptions" },
  { name: "cancelPendingProxyResidentCreate", service: "proxyResidents", method: "cancelPendingProxyResidentCreate", mode: "operator", options: "callableOptions" },
  { name: "listProxyResidents", service: "proxyResidents", method: "listProxyResidents", mode: "operator", options: "callableOptions" },
  { name: "getProxyTaskStatus", service: "proxyResidents", method: "getProxyTaskStatus", mode: "operator", options: "callableOptions" },
  { name: "updateProxyResidentAssistance", service: "proxyResidents", method: "updateProxyAssistance", mode: "operator", options: "callableOptions" },
  { name: "updateProxyTaskStatus", service: "proxyResidents", method: "updateProxyTaskStatus", mode: "operator", options: "callableOptions" },
  { name: "deleteResidentData", service: "residentDataDeletion", method: "deleteResidentData", mode: "operator", options: "callableOptions" },
  { name: "deleteOwnResidentData", service: "residentDataDeletion", method: "deleteOwnResidentData", mode: "resident", options: "callableOptions" },
  { name: "getAssistanceVolunteerData", service: "assistanceAssignments", method: "getVolunteerData", mode: "resident", options: "callableOptions" },
  { name: "updateAssistanceVolunteerConsent", service: "assistanceAssignments", method: "updateVolunteerConsent", mode: "resident", options: "callableOptions" },
  { name: "listAvailableAssistanceHelpers", service: "assistanceAssignments", method: "listVolunteerHelpers", mode: "operator", options: "callableOptions" },
  { name: "createAssistanceHelperAssignment", service: "assistanceAssignments", method: "createHelperAssignment", mode: "operator", options: "callableOptions" },
  { name: "respondToAssistanceAssignment", service: "assistanceAssignments", method: "respondToHelperAssignment", mode: "resident", options: "callableOptions" },
  { name: "registerResidentPushToken", service: "taskNotifications", method: "registerResidentPushToken", mode: "resident", options: "callableOptions" },
  { name: "unregisterResidentPushToken", service: "taskNotifications", method: "unregisterResidentPushToken", mode: "resident", options: "callableOptions" },
  { name: "registerPendampingPushToken", service: "taskNotifications", method: "registerPendampingPushToken", mode: "operator", options: "callableOptions" },
  { name: "unregisterPendampingPushToken", service: "taskNotifications", method: "unregisterPendampingPushToken", mode: "operator", options: "callableOptions" },
  { name: "listTaskNotificationAudit", service: "taskNotifications", method: "listAuditEvents", mode: "operator", options: "callableOptions" },
  { name: "submitResidentProposal", service: "residentProposals", method: "submitResidentProposal", mode: "resident", options: "callableOptions" },
  { name: "listMyResidentProposals", service: "residentProposals", method: "listMyResidentProposals", mode: "resident", options: "callableOptions" },
  { name: "listResidentProposals", service: "residentProposals", method: "listResidentProposals", mode: "operator", options: "callableOptions" },
  { name: "reviewResidentProposal", service: "residentProposals", method: "reviewResidentProposal", mode: "operator", options: "callableOptions" },
  { name: "mapResidentProposalToDraft", service: "residentProposals", method: "mapResidentProposalToDraft", mode: "operator", options: "callableOptions" },
  { name: "submitTreePoint", service: "treePoints", method: "submitTreePoint", mode: "resident", options: "callableOptions" },
  { name: "verifyTreePoint", service: "treePoints", method: "verifyTreePoint", mode: "operator", options: "callableOptions" },
];
