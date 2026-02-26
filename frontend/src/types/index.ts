export interface Input {
  id: string
  source_type: 'email' | 'voice' | 'meeting' | 'bug' | 'other'
  raw_text: string
  author_id?: string
  created_at: string
}

export interface Item {
  id: string
  input_id: string
  text: string
  intent_code: string
  domain_code: string
  confidence: number
  position: number
}

export interface Action {
  id: string
  item_id: string
  type: 'CREATE_ISSUE' | 'ANSWER' | 'STORE' | 'REJECT' | 'HOLD' | 'LINK_EXISTING'
  status: string
  reason?: string
}

export interface Issue {
  id: string
  title: string
  status: 'open' | 'doing' | 'done'
  priority: number
  created_at: string
}
