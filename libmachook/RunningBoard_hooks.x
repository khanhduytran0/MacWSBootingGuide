@import CydiaSubstrate;

%hook RBSEmbeddedAppProcessIdentity
%new
- (instancetype)initWithRBSXPCCoder:(id)coder {
    return nil;
}
%end
