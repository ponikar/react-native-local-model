#import "LocalModel.h"
#include "llama.h"
#include <regex>
#include <vector>
#include "common.h"
#include <string>

using namespace std;

@implementation LocalModel {
    llama_context* ctx;
    llama_model* model;
}

RCT_EXPORT_MODULE()

bool is_valid_char(char c) {
    return (c >= 32 && c <= 126) || c == '\n' || c == '\t';
}

std::string generate_tokens(llama_context* ctx, llama_model* model, const std::string& prompt,
                            int max_tokens, float temperature, float top_p, float top_k) {
    std::vector<llama_token> tokens(llama_n_ctx(ctx));
    int n_tokens = llama_tokenize(model, prompt.c_str(), prompt.length(), tokens.data(), tokens.size(), true, false);
    
    if (n_tokens < 0) {
        return "Error: Failed to tokenize prompt";
    }
    
    if (llama_decode(ctx, llama_batch_get_one(tokens.data(), n_tokens, 0, 0)) != 0) {
        return "Error: Failed to process prompt";
    }
    
    std::string response;
    std::vector<llama_token> output_tokens;
    const int n_vocab = llama_n_vocab(model);
    std::vector<llama_token_data> candidates(n_vocab);
    llama_token_data_array candidates_p = { candidates.data(), candidates.size(), false };
    
    for (int i = 0; i < max_tokens; i++) {
        if (llama_decode(ctx, llama_batch_get_one(&tokens[n_tokens + i], 1, n_tokens + i, 0)) != 0) {
            break;
        }
        
        const float* logits = llama_get_logits(ctx);
        candidates_p.size = n_vocab;
        
        for (llama_token token_id = 0; token_id < n_vocab; token_id++) {
            candidates[token_id] = { token_id, logits[token_id], 0.0f };
        }
        
        llama_sample_top_k(ctx, &candidates_p, top_k, 1);
        llama_sample_top_p(ctx, &candidates_p, top_p, 1);
        llama_sample_temp(ctx, &candidates_p, temperature);
        
        llama_token new_token = llama_sample_token(ctx, &candidates_p);
        
        if (new_token == llama_token_eos(model)) {
            break;
        }
        
        output_tokens.push_back(new_token);
        const char* token_str = llama_token_get_text(model, new_token);
        
        if (token_str != nullptr) {
            response += token_str;
        }
    }
    
    return clean_text(response);
}

std::string clean_text(const std::string& input) {
    std::string output;
    bool last_was_space = true;
    
    for (char c : input) {
        if (is_valid_char(c)) {
            if (c == ' ' || c == '\n' || c == '\t') {
                if (!last_was_space) {
                    output += ' ';
                    last_was_space = true;
                }
            } else {
                output += c;
                last_was_space = false;
            }
        }
    }
    
    while (!output.empty() && output.back() == ' ') {
        output.pop_back();
    }
    
    return output;
}

void apply_repetition_penalty(llama_token_data_array* candidates, const std::vector<llama_token>& output_tokens, int repeat_last_n, float repeat_penalty) {
    int start_idx = std::max(0, (int)output_tokens.size() - repeat_last_n);
    
    for (size_t i = 0; i < candidates->size; ++i) {
        llama_token token_id = candidates->data[i].id;
        
        for (size_t j = start_idx; j < output_tokens.size(); ++j) {
            if (token_id == output_tokens[j]) {
                candidates->data[i].logit /= repeat_penalty;
                break;
            }
        }
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        llama_backend_init();
        NSLog(@"LocalModel: Backend initialized");
    }
    return self;
}

RCT_EXPORT_METHOD(loadModelAndAskQuestion:(NSString *)modelName
                  question:(NSString *)question
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    NSString *modelPath = [[NSBundle mainBundle] pathForResource:@"tinyllama-1.1b-chat-v1.0.Q2_K" ofType:@"gguf"];
    NSLog(@"LocalModel: Attempting to load model from path: %@", modelPath);
    
    if (modelPath == nil) {
        NSLog(@"LocalModel: Model file not found");
        reject(@"MODEL_NOT_FOUND", @"Model file not found in the app bundle", nil);
        return;
    }
    
    struct llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;
    model = llama_load_model_from_file([modelPath UTF8String], model_params);
    
    if (model == NULL) {
        NSLog(@"LocalModel: Failed to load model");
        reject(@"MODEL_LOAD_ERROR", @"Failed to load model", nil);
        return;
    }
    
    NSLog(@"LocalModel: Model loaded successfully. Vocab size: %d", llama_n_vocab(model));
    
    struct llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = 2048;
    ctx_params.n_batch = 512;
    ctx_params.n_threads = 4;
    ctx_params.n_threads_batch = 4;
    
    ctx = llama_new_context_with_model(model, ctx_params);
    
    if (ctx == NULL) {
        NSLog(@"LocalModel: Failed to create context");
        llama_free_model(model);
        reject(@"CONTEXT_CREATION_ERROR", @"Failed to create context", nil);
        return;
    }
    
    NSLog(@"LocalModel: Context created successfully");
    
    NSString *systemPrompt = @"You are a helpful, respectful and honest assistant. Always answer as helpfully as possible, while being safe.";
    NSString *fullPrompt = [NSString stringWithFormat:@"[INST] <<SYS>>%@<</SYS>>\n\nHuman: %@\n\nAssistant:", systemPrompt, question];
    const char* prompt = [fullPrompt UTF8String];
    
    std::vector<llama_token> tokens(llama_n_ctx(ctx));
    int n_tokens = llama_tokenize(model, prompt, strlen(prompt), tokens.data(), tokens.size(), true, false);
    
    if (n_tokens < 0) {
        NSLog(@"LocalModel: Error tokenizing prompt");
        llama_free(ctx);
        llama_free_model(model);
        reject(@"TOKENIZATION_ERROR", @"Failed to tokenize input", nil);
        return;
    }
    
    NSLog(@"LocalModel: Input tokenized successfully. Number of tokens: %d", n_tokens);
    
    if (llama_decode(ctx, llama_batch_get_one(tokens.data(), n_tokens, 0, 0)) != 0) {
        NSLog(@"LocalModel: Error processing prompt");
        llama_free(ctx);
        llama_free_model(model);
        reject(@"DECODE_ERROR", @"Failed to process input", nil);
        return;
    }
    
    std::string response;
    std::vector<llama_token> output_tokens;
    float temperature = 0.7f;
    int top_k = 20;
    float top_p = 0.75f;
    int max_tokens = 100;
    float repeat_penalty = 1.1f;
    int repeat_last_n = 64;
    
    
    llama_batch batch = llama_batch_init(2048, 0, 1);
           
    const int n_vocab = llama_n_vocab(model);
    std::vector<llama_token_data> candidates(n_vocab);
    llama_token_data_array candidates_p = { candidates.data(), candidates.size(), false };
    
    for (int i = 0; i < max_tokens; i++) {
        if (llama_decode(ctx, llama_batch_get_one(&tokens[n_tokens + i], 1, n_tokens + i, 0)) != 0) {
            NSLog(@"Failed to update context");
            break;
        }
        
        const float* logits = llama_get_logits(ctx);
        
        for (int token_id = 0; token_id < n_vocab; token_id++) {
            candidates[token_id] = {token_id, logits[token_id], 0.0f};
        }
        
        candidates_p.size = n_vocab;
        candidates_p.sorted = false;
        
        // apply_repetition_penalty(&candidates_p, output_tokens, repeat_last_n, repeat_penalty);
        
        llama_sample_top_k(ctx, &candidates_p, top_k, 1);
        llama_sample_top_p(ctx, &candidates_p, top_p, 1);
        llama_sample_temp(ctx, &candidates_p, temperature);
        
        llama_token new_token = llama_sample_token(ctx, &candidates_p);
        
        if (new_token == llama_token_eos(model)) {
            break;
        }
        
        output_tokens.push_back(new_token);
        std::string token_text = llama_token_to_piece(ctx, new_token);
        
        NSLog(@"TOKEN --> %s", token_text.c_str());
    
        
        if (response.length() >= 100) {
            break;
        }
    }
    
    std::string cleaned_response = clean_text(response);
    NSLog(@"LocalModel: Final generated response: %s", cleaned_response.c_str());
    
    llama_free(ctx);
    llama_free_model(model);
    NSLog(@"LocalModel: Resources freed");
    
    //    resolve([]);
}

- (void)dealloc {
    llama_backend_free();
    NSLog(@"LocalModel: Backend freed");
}

@end
