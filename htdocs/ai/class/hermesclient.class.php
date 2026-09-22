<?php
/* Copyright (C) 2026      OpenAI */

/**
 * \file    htdocs/ai/class/hermesclient.class.php
 * \ingroup ai
 * \brief   Small OpenAI-compatible client for the Hermes dashboard.
 */

require_once DOL_DOCUMENT_ROOT.'/core/lib/geturl.lib.php';

/**
 * Client used by the AI dashboard to send business questions to Hermes.
 *
 * Hermes is intentionally configured in conf.php rather than in the
 * database. This keeps the endpoint and credentials outside normal business
 * data exports and lets the customer choose the deployment later.
 */
class HermesClient
{
	/** @var string OpenAI-compatible endpoint or base URL */
	private $endpoint;

	/** @var string Optional bearer token */
	private $apiKey;

	/** @var string Model name */
	private $model;

	/** @var int HTTP timeout in seconds */
	private $timeout;

	/** @var string Optional system prompt override */
	private $systemPrompt;

	/**
	 * Build a client from the global variables defined in conf.php.
	 */
	public function __construct()
	{
		global $dolibarr_hermes_endpoint, $dolibarr_hermes_api_key, $dolibarr_hermes_model;
		global $dolibarr_hermes_timeout, $dolibarr_hermes_system_prompt;

		$this->endpoint = trim((string) ($dolibarr_hermes_endpoint ?? ''));
		$this->apiKey = (string) ($dolibarr_hermes_api_key ?? '');
		$this->model = trim((string) ($dolibarr_hermes_model ?? ''));
		$this->timeout = (int) ($dolibarr_hermes_timeout ?? 120);
		$this->systemPrompt = trim((string) ($dolibarr_hermes_system_prompt ?? ''));

		if ($this->model === '') {
			$this->model = 'hermes';
		}
		if ($this->timeout < 5) {
			$this->timeout = 120;
		}
	}

	/**
	 * Whether an endpoint was configured.
	 *
	 * @return bool True when the dashboard can attempt a request.
	 */
	public function isConfigured()
	{
		return $this->endpoint !== '';
	}

	/**
	 * Ask Hermes a question using the supplied ERP context.
	 *
	 * The endpoint is compatible with the common /v1/chat/completions shape.
	 * A full chat-completions URL is accepted; a base URL receives the standard
	 * "/v1/chat/completions" suffix.
	 *
	 * @param string $question User-entered business question
	 * @param string $context  Current dashboard data supplied as grounding
	 * @return array{success:bool,answer?:string,error?:string}
	 */
	public function ask($question, $context = '')
	{
		$question = trim((string) $question);
		if ($question === '') {
			return array('success' => false, 'error' => 'Question is empty.');
		}
		if (!$this->isConfigured()) {
			return array('success' => false, 'error' => 'Hermes endpoint is not configured.');
		}

		$system = $this->systemPrompt;
		if ($system === '') {
			$system = '你是 ERP 制造业务助手。请只依据用户问题和提供的业务数据回答，'
				. '不要编造不存在的订单、库存或金额。回答使用简洁的中文，先给结论，'
				. '再说明关键依据；如果数据不足，请明确说明需要补充什么数据。';
		}

		$userMessage = $question;
		if (trim((string) $context) !== '') {
			$userMessage .= "\n\n以下是当前 AI 看板数据，请将其作为事实依据：\n".$context;
		}

		$payload = array(
			'model' => $this->model,
			'messages' => array(
				array('role' => 'system', 'content' => $system),
				array('role' => 'user', 'content' => $userMessage),
			),
			'temperature' => 0.2,
			'stream' => false,
		);
		$jsonPayload = json_encode($payload, JSON_UNESCAPED_UNICODE);
		if ($jsonPayload === false) {
			return array('success' => false, 'error' => 'Cannot encode Hermes request.');
		}

		$headers = array('Content-Type: application/json', 'Accept: application/json');
		if ($this->apiKey !== '') {
			$headers[] = 'Authorization: Bearer '.$this->apiKey;
		}

		global $dolibarr_ai_allow_local_endpoints;
		$localUrl = (int) ($dolibarr_ai_allow_local_endpoints ?? 0);
		$url = $this->getRequestUrl();
		$result = getURLContent(
			$url,
			'POSTALREADYFORMATED',
			$jsonPayload,
			1,
			$headers,
			array('http', 'https'),
			$localUrl,
			-1,
			0,
			$this->timeout
		);

		$httpCode = (int) ($result['http_code'] ?? 0);
		if (!empty($result['curl_error_no'])) {
			dol_syslog('Hermes dashboard request failed: cURL #'.(int) $result['curl_error_no'], LOG_WARNING);
			return array('success' => false, 'error' => 'Hermes connection failed.');
		}

		$body = (string) ($result['content'] ?? '');
		$response = json_decode($body, true);
		if (!is_array($response)) {
			dol_syslog('Hermes dashboard returned invalid JSON, HTTP '.$httpCode, LOG_WARNING);
			return array('success' => false, 'error' => 'Hermes returned an invalid response (HTTP '.$httpCode.').');
		}
		if ($httpCode < 200 || $httpCode >= 300 || isset($response['error'])) {
			$errorMessage = 'Hermes request failed (HTTP '.$httpCode.').';
			if (isset($response['error']['message'])) {
				$errorMessage .= ' '.dol_trunc((string) $response['error']['message'], 300);
			}
			dol_syslog('Hermes dashboard '.$errorMessage, LOG_WARNING);
			return array('success' => false, 'error' => $errorMessage);
		}

		$answer = $this->extractAnswer($response);
		if ($answer === '') {
			dol_syslog('Hermes dashboard response has no text content', LOG_WARNING);
			return array('success' => false, 'error' => 'Hermes returned no answer.');
		}

		return array('success' => true, 'answer' => $answer);
	}

	/**
	 * Return the full chat-completions URL.
	 *
	 * @return string Request URL
	 */
	private function getRequestUrl()
	{
		$url = rtrim($this->endpoint, '/');
		if (strpos($url, '/chat/completions') === false && strpos($url, '/generate') === false) {
			$url .= (strpos($url, '/v1') === false ? '/v1' : '').'/chat/completions';
		}

		return $url;
	}

	/**
	 * Extract text from common OpenAI-compatible and simple Hermes responses.
	 *
	 * @param array<string,mixed> $response Decoded response
	 * @return string Answer text
	 */
	private function extractAnswer(array $response)
	{
		$content = $response['choices'][0]['message']['content'] ?? null;
		if ($content === null) {
			$content = $response['choices'][0]['text'] ?? ($response['output_text'] ?? null);
		}
		if ($content === null) {
			$content = $response['answer'] ?? ($response['response'] ?? ($response['content'] ?? null));
		}
		if (is_array($content)) {
			$parts = array();
			foreach ($content as $part) {
				if (is_string($part)) {
					$parts[] = $part;
				} elseif (is_array($part) && isset($part['text'])) {
					$parts[] = (string) $part['text'];
				}
			}
			$content = implode('', $parts);
		}

		return trim((string) $content);
	}
}
