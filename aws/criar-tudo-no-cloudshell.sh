#!/bin/bash
# ==============================================================================
#  CH.Com Cofre - cria TUDO na AWS, de uma vez
#
#  RODE ISTO NO AWS CLOUDSHELL, e nao no servidor.
#
#  O CloudShell fica dentro do console da AWS e ja esta autenticado como voce.
#  Nenhuma credencial sai da sua conta, nenhuma passa por ninguem.
#
#  COMO ABRIR
#    console.aws.amazon.com  ->  icone de terminal no canto superior direito
#    (ou: https://us-east-2.console.aws.amazon.com/cloudshell)
#
#  COMO USAR
#    Cole este arquivo inteiro, aperte Enter, e guarde as duas chaves que
#    aparecem no fim.
# ==============================================================================
set -e

BUCKET="backup-aws-ch"
REGIAO="us-east-2"
CARTORIO="${1:-cartorio-01}"

echo ""
echo "  bucket : $BUCKET  ($REGIAO)"
echo "  usuario: cofre-$CARTORIO"
echo ""

# ---------------------------------------------------------------- 1. o bucket
# --object-lock-enabled-for-bucket SO funciona na CRIACAO, e ja liga o
# versionamento junto. Depois de criado nao da para ligar do mesmo jeito.
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "  [ja existe] bucket $BUCKET"
else
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGIAO" \
    --create-bucket-configuration LocationConstraint="$REGIAO" \
    --object-lock-enabled-for-bucket > /dev/null
  echo "  [ok] bucket criado, com Bloqueio de Objeto e versionamento"
fi

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "  [ok] acesso publico bloqueado"

# GOVERNANCE, e nao COMPLIANCE: em Compliance nem a conta raiz remove, e 2 TB
# subidos por engano viram 180 dias de fatura sem saida.
# 180 dias porque e o minimo que o Deep Archive ja cobra - nao custa nada a mais.
aws s3api put-object-lock-configuration \
  --bucket "$BUCKET" \
  --object-lock-configuration '{"ObjectLockEnabled":"Enabled","Rule":{"DefaultRetention":{"Mode":"GOVERNANCE","Days":180}}}'
echo "  [ok] retencao de 180 dias em modo Governanca"

# ------------------------------------------------------- 2. a politica e o usuario
# Sem s3:DeleteObject, de proposito: o agente nunca apaga nada na nuvem, e um
# servidor invadido nao tem como apagar o proprio backup.
cat > /tmp/politica.json <<POLITICA
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListarSomenteOPrefixoDesteCartorio",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::$BUCKET",
      "Condition": { "StringLike": { "s3:prefix": [ "$CARTORIO/*", "$CARTORIO" ] } }
    },
    {
      "Sid": "EscreverLerEDescongelarSomenteNoProprioPrefixo",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject", "s3:GetObject", "s3:GetObjectVersion",
        "s3:RestoreObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::$BUCKET/$CARTORIO/*"
    },
    {
      "Sid": "SaberEmQualRegiaoOBucketEsta",
      "Effect": "Allow",
      "Action": "s3:GetBucketLocation",
      "Resource": "arn:aws:s3:::$BUCKET"
    }
  ]
}
POLITICA

CONTA=$(aws sts get-caller-identity --query Account --output text)
ARN="arn:aws:iam::${CONTA}:policy/cofre-$CARTORIO"

if aws iam get-policy --policy-arn "$ARN" >/dev/null 2>&1; then
  echo "  [ja existe] politica cofre-$CARTORIO"
else
  aws iam create-policy --policy-name "cofre-$CARTORIO" \
    --policy-document file:///tmp/politica.json > /dev/null
  echo "  [ok] politica cofre-$CARTORIO criada"
fi

if aws iam get-user --user-name "cofre-$CARTORIO" >/dev/null 2>&1; then
  echo "  [ja existe] usuario cofre-$CARTORIO"
else
  aws iam create-user --user-name "cofre-$CARTORIO" > /dev/null
  echo "  [ok] usuario cofre-$CARTORIO criado (sem acesso ao console)"
fi

aws iam attach-user-policy --user-name "cofre-$CARTORIO" --policy-arn "$ARN"
echo "  [ok] politica anexada"

# ------------------------------------------------------------------ 3. as chaves
echo ""
echo "  ==========================================================="
echo "   AS DUAS CHAVES - a Secret aparece UMA VEZ SO"
echo "  ==========================================================="
aws iam create-access-key --user-name "cofre-$CARTORIO" \
  --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text | \
  awk '{ print ""; print "   Access Key ID : " $1; print "   Secret        : " $2; print "" }'
echo "  ==========================================================="
echo ""
echo "  Agora, no servidor do cartorio:"
echo "    1. rode o instalador"
echo "    2. no assistente, cartorio = $CARTORIO"
echo "    3. bucket = $BUCKET   regiao = $REGIAO"
echo "    4. cole as duas chaves acima"
echo ""
