#import "LocalModel.h"
#include "llama.h"
#include <string>
#include <vector>

@implementation LocalModel {
    llama_context* ctx;
    llama_model* model;
}

RCT_EXPORT_MODULE()

- (instancetype)init {
    self = [super init];
    if (self) {
        llama_backend_init();
    }
    return self;
}

RCT_EXPORT_METHOD(loadModelAndAskQuestion:(NSString *)modelName
                  question:(NSString *)question
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    NSString *modelPath = [[NSBundle mainBundle] pathForResource:@"tinyllama-1.1b-chat-v1.0.Q2_K" ofType:@"gguf"];
    
    if (modelPath == nil) {
        // If not found in the bundle, try to load from the same directory as this file
        NSString *currentDirectory = [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
        modelPath = [currentDirectory stringByAppendingPathComponent:@"sample_model.gguf"];
    }
    
    NSLog(@"Debug - Model Path: %@", modelPath);

    
    if (modelPath == nil) {
        reject(@"MODEL_NOT_FOUND", @"Model file not found in the app bundle", nil);
        return;
    }

    // Load the model
    struct llama_model_params model_params = llama_model_default_params();
    model = llama_load_model_from_file([modelPath UTF8String], model_params);
    
    if (model == NULL) {
        reject(@"MODEL_LOAD_ERROR", @"Failed to load model", nil);
        return;
    }
    
    // Initialize context
    struct llama_context_params ctx_params = llama_context_default_params();
    ctx = llama_new_context_with_model(model, ctx_params);
    
    if (ctx == NULL) {
        llama_free_model(model);
        reject(@"CONTEXT_CREATION_ERROR", @"Failed to create context", nil);
        return;
    }
    
    // Tokenize the question
    std::string prompt = [question UTF8String];
    std::vector<llama_token> tokens(prompt.length() + 1);  // +1 for potential BOS token
    int n_tokens = llama_tokenize(model, prompt.c_str(), prompt.length(), tokens.data(), tokens.size(), true, false);
    
    if (n_tokens < 0) {
        llama_free(ctx);
        llama_free_model(model);
        reject(@"TOKENIZATION_ERROR", @"Failed to tokenize input", nil);
        return;
    }
    
    // Create a batch with the tokenized input
    llama_batch batch = llama_batch_get_one(tokens.data(), n_tokens, 0, 0);
    
    // Process the batch
    if (llama_decode(ctx, batch) != 0) {
        llama_free(ctx);
        llama_free_model(model);
        reject(@"DECODE_ERROR", @"Failed to process input", nil);
        return;
    }
    
    // Generate response
    std::string response;
    for (int i = 0; i < 100; i++) {  // Generate up to 100 tokens
        llama_token new_token = llama_sample_token(ctx, NULL);
        
        if (new_token == llama_token_eos(model)) {
            break;
        }
        
        const char* token_text = llama_token_get_text(model, new_token);
        if (token_text != NULL) {
            response += token_text;
        }
        
        if (llama_decode(ctx, llama_batch_get_one(&new_token, 1, n_tokens + i, 0)) != 0) {
            break;
        }
    }
    
    // Clean up
    llama_free(ctx);
    llama_free_model(model);
    
    // Return the response
    resolve(@(response.c_str()));
}

- (void)dealloc {
    llama_backend_free();
}

@end
