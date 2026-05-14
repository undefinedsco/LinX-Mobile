import { LINX_CONTRACT, LINX_NAMESPACE } from '../contract';
import type { LinxMessageRole, LinxMessageStatus } from '../types';

const prefixes = `
PREFIX dcterms: <${LINX_NAMESPACE.dcterms}>
PREFIX foaf: <${LINX_NAMESPACE.foaf}>
PREFIX meeting: <${LINX_NAMESPACE.meeting}>
PREFIX schema: <${LINX_NAMESPACE.schema}>
PREFIX sioc: <${LINX_NAMESPACE.sioc}>
PREFIX udfs: <${LINX_NAMESPACE.udfs}>
PREFIX wf: <${LINX_NAMESPACE.wf}>
PREFIX xsd: <${LINX_NAMESPACE.xsd}>
`.trim();

export function escapeLiteral(value: string): string {
  if (value.includes('\n') || value.includes('\r') || value.includes('"')) {
    const escaped = value
      .replace(/\\/g, '\\\\')
      .replace(/"""/g, '\\"\\"\\"');
    return `"""${escaped}"""`;
  }

  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

export function dateLiteral(date: Date): string {
  return `"${date.toISOString()}"^^xsd:dateTime`;
}

export function chatResourceTurtle(input: {
  chatUri: string;
  createdAt: Date;
}): string {
  return `
${prefixes}

<${input.chatUri}> a meeting:LongChat ;
  dcterms:title ${escapeLiteral(LINX_CONTRACT.defaultChatTitle)} ;
  dcterms:created ${dateLiteral(input.createdAt)} ;
  dcterms:modified ${dateLiteral(input.createdAt)} ;
  udfs:lastActiveAt ${dateLiteral(input.createdAt)} .
`.trimStart();
}

export function agentResourceTurtle(input: {
  agentUri: string;
  modelId: string;
  createdAt: Date;
}): string {
  return `
${prefixes}

<${input.agentUri}> a foaf:Agent ;
  foaf:name ${escapeLiteral(LINX_CONTRACT.defaultAgentName)} ;
  udfs:provider ${escapeLiteral('xpod')} ;
  udfs:model ${escapeLiteral(input.modelId)} ;
  dcterms:created ${dateLiteral(input.createdAt)} ;
  dcterms:modified ${dateLiteral(input.createdAt)} .
`.trimStart();
}

export function emptyTurtleResource(): string {
  return '# LinX message store\n';
}

export function threadsQuery(input: { chatUri: string; limit: number }): string {
  return `
${prefixes}

SELECT ?thread ?title ?workspace ?createdAt ?updatedAt
WHERE {
  ?thread a sioc:Thread ;
          sioc:has_parent <${input.chatUri}> ;
          dcterms:created ?createdAt .
  OPTIONAL { ?thread dcterms:title ?title . }
  OPTIONAL { ?thread udfs:workspace ?workspace . }
  OPTIONAL { ?thread dcterms:modified ?updatedAt . }
}
ORDER BY DESC(COALESCE(?updatedAt, ?createdAt))
LIMIT ${input.limit}
`.trimStart();
}

export function messagesQuery(input: {
  threadUri: string;
  limit?: number;
  offset?: number;
}): string {
  const offset = input.offset ?? 0;
  const pagination =
    typeof input.limit === 'number'
      ? `\nLIMIT ${input.limit}\nOFFSET ${offset}`
      : offset > 0
        ? `\nOFFSET ${offset}`
        : '';

  return `
${prefixes}

SELECT ?message ?maker ?role ?content ?richContent ?status ?createdAt ?updatedAt
WHERE {
  <${input.threadUri}> sioc:has_member ?message .
  ?message a meeting:Message ;
           foaf:maker ?maker ;
           udfs:messageType ?role ;
           sioc:content ?content ;
           dcterms:created ?createdAt .
  OPTIONAL { ?message sioc:richContent ?richContent . }
  OPTIONAL { ?message udfs:messageStatus ?status . }
  OPTIONAL { ?message dcterms:modified ?updatedAt . }
}
ORDER BY DESC(?createdAt)${pagination}
`.trimStart();
}

export function createThreadPatch(input: {
  chatUri: string;
  threadUri: string;
  title: string;
  workspace?: string;
  createdAt: Date;
}): string {
  const workspaceTriple = input.workspace
    ? `\n    udfs:workspace <${input.workspace}> ;`
    : '';

  return `
${prefixes}

INSERT DATA {
  <${input.threadUri}> a sioc:Thread ;
    sioc:has_parent <${input.chatUri}> ;
    dcterms:title ${escapeLiteral(input.title)} ;${workspaceTriple}
    dcterms:created ${dateLiteral(input.createdAt)} ;
    dcterms:modified ${dateLiteral(input.createdAt)} .
}
`.trimStart();
}

export function insertMessagePatch(input: {
  chatUri: string;
  threadUri: string;
  messageUri: string;
  makerUri: string;
  role: LinxMessageRole;
  content: string;
  status: LinxMessageStatus;
  createdAt: Date;
  richContent?: string;
}): string {
  const richContentTriple = input.richContent
    ? `\n    sioc:richContent ${escapeLiteral(input.richContent)} ;`
    : '';

  return `
${prefixes}

INSERT DATA {
  <${input.chatUri}> wf:message <${input.messageUri}> .
  <${input.threadUri}> sioc:has_member <${input.messageUri}> .
  <${input.messageUri}> a meeting:Message ;
    foaf:maker <${input.makerUri}> ;
    udfs:messageType ${escapeLiteral(input.role)} ;
    sioc:content ${escapeLiteral(input.content)} ;${richContentTriple}
    udfs:messageStatus ${escapeLiteral(input.status)} ;
    dcterms:created ${dateLiteral(input.createdAt)} ;
    dcterms:modified ${dateLiteral(input.createdAt)} .
}
`.trimStart();
}

export function patchActivity(input: {
  chatUri: string;
  threadUri: string;
  preview: string;
  updatedAt: Date;
}): string {
  return `
${prefixes}

DELETE {
  <${input.chatUri}> schema:text ?oldPreview .
  <${input.chatUri}> udfs:lastActiveAt ?oldLastActiveAt .
  <${input.chatUri}> dcterms:modified ?oldChatUpdatedAt .
  <${input.threadUri}> dcterms:modified ?oldThreadUpdatedAt .
}
INSERT {
  <${input.chatUri}> schema:text ${escapeLiteral(input.preview)} .
  <${input.chatUri}> udfs:lastActiveAt ${dateLiteral(input.updatedAt)} .
  <${input.chatUri}> dcterms:modified ${dateLiteral(input.updatedAt)} .
  <${input.threadUri}> dcterms:modified ${dateLiteral(input.updatedAt)} .
}
WHERE {
  OPTIONAL { <${input.chatUri}> schema:text ?oldPreview . }
  OPTIONAL { <${input.chatUri}> udfs:lastActiveAt ?oldLastActiveAt . }
  OPTIONAL { <${input.chatUri}> dcterms:modified ?oldChatUpdatedAt . }
  OPTIONAL { <${input.threadUri}> dcterms:modified ?oldThreadUpdatedAt . }
}
`.trimStart();
}
